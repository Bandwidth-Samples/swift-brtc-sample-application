import AVFoundation
import SwiftUI
import UIKit
import BandwidthRTC

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case ringing   // CallKit incoming call UI shown, awaiting answer/decline
    case inCall
}

@Observable
final class CallViewModel: @unchecked Sendable {
    // MARK: - UI State

    var connectionState: ConnectionState = .disconnected
    var serverURL: String = "http://localhost:3000"
    var phoneNumber: String = ""
    var isMicEnabled: Bool = true
    var isPlayingMedia: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var showDialpad: Bool = false
    var statusText: String = ""
    var callDuration: TimeInterval = 0
    var callStats: CallStatsSnapshot?
    var showStatsOverlay: Bool = false

    // MARK: - Audio Waveform

    /// Rolling buffer of normalized (0–1) mic amplitude samples for the outgoing audio waveform.
    var localAudioLevels: [Float] = []
    /// Rolling buffer of normalized (0–1) remote audio level samples for the incoming audio waveform.
    var remoteAudioLevels: [Float] = []

    var callDurationFormatted: String {
        let minutes = Int(callDuration) / 60
        let seconds = Int(callDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var currentEndpointId: String? {
        endpointId
    }

    var formattedPhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }
        if digits.count == 10 {
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3).prefix(3)
            let last = digits.dropFirst(6)
            return "(\(area)) \(mid)-\(last)"
        } else if digits.count == 11, digits.first == "1" {
            let area = digits.dropFirst(1).prefix(3)
            let mid = digits.dropFirst(4).prefix(3)
            let last = digits.dropFirst(7)
            return "+1 (\(area)) \(mid)-\(last)"
        }
        return phoneNumber
    }

    /// E.164 formatted number for API calls (e.g. +12225551234)
    var e164PhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }
        if digits.count == 10 {
            return "+1\(digits)"
        } else if digits.count == 11, digits.first == "1" {
            return "+\(digits)"
        }
        return phoneNumber
    }

    // MARK: - Call History

    let callHistory = CallHistoryManager()

    // MARK: - Private

    private let brtc = BandwidthRTCClient(logLevel: .debug)
    private let tokenService = TokenService()
    private var localStream: RtcStream?
    /// Strong reference to the remote stream so the audio track isn't released.
    private var remoteStream: RtcStream?
    private var callTimer: Timer?
    private var statsTimer: Timer?
    private var previousStatsSnapshot: CallStatsSnapshot?
    private let waveformCapacity = 50
    /// Tracks the active call record so we can update its duration when the call ends.
    private var activeCallRecordId: UUID?
    /// Our BRTC endpoint ID (for the simulated incoming call API).
    private var endpointId: String?

    init() {
        brtc.callDelegate = self
        brtc.callKitEnabled = true
        setupStreamCallbacks()
    }

    // MARK: - Actions

    func connect() {
        guard connectionState == .disconnected else { return }
        connectionState = .connecting
        statusText = "Fetching token..."

        Task { @MainActor in
            do {
                // Request microphone permission up-front before WebRTC setup.
                let micGranted: Bool
                if #available(iOS 17.0, *) {
                    micGranted = await AVAudioApplication.requestRecordPermission()
                } else {
                    micGranted = await withCheckedContinuation { continuation in
                        AVAudioSession.sharedInstance().requestRecordPermission { granted in
                            continuation.resume(returning: granted)
                        }
                    }
                }
                guard micGranted else {
                    connectionState = .disconnected
                    showErrorMessage("Microphone permission is required for calls")
                    return
                }

                let (token, serverEndpointId) = try await tokenService.fetchToken(serverURL: serverURL)
                self.endpointId = serverEndpointId
                statusText = "Connecting to BRTC..."

                try await brtc.connect(authParams: RtcAuthParams(endpointToken: token))

                statusText = "Publishing media..."
                let stream = try await brtc.publish(audio: true)
                localStream = stream

                connectionState = .connected
                statusText = "Connected"
            } catch {
                connectionState = .disconnected
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        callTimer?.invalidate()
        callTimer = nil
        callDuration = 0
        stopStatsPolling()
        stopAudioLevelMonitoring()
        Task {
            await brtc.disconnect()
        }
        localStream = nil
        remoteStream = nil
        endpointId = nil
        connectionState = .disconnected
        statusText = ""
    }

    func dialpadInput(_ digit: String) {
        phoneNumber.append(digit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func call() {
        guard !phoneNumber.isEmpty else {
            showErrorMessage("Enter a phone number")
            return
        }

        connectionState = .inCall
        statusText = "Calling \(formattedPhoneNumber)..."

        // Record outbound call in history
        let record = CallDetailRecord(
            id: UUID(),
            phoneNumber: e164PhoneNumber,
            direction: .outbound,
            timestamp: Date(),
            duration: 0
        )
        callHistory.addRecord(record)
        activeCallRecordId = record.id

        Task { @MainActor in
            do {
                let result = try await brtc.requestOutboundConnection(
                    id: e164PhoneNumber,
                    type: .phoneNumber
                )
                if result.accepted {
                    statusText = "Ringing..."
                } else {
                    statusText = "Call not accepted"
                }
            } catch {
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    func hangup() {
        stopMedia()
        finalizeCallRecord()
        callTimer?.invalidate()
        callTimer = nil
        callDuration = 0
        stopStatsPolling()
        stopAudioLevelMonitoring()

        Task { @MainActor in
            try? await brtc.endCall()
            connectionState = .connected
            statusText = "Connected"
            remoteStream = nil
        }
    }

    func toggleMic() {
        isMicEnabled.toggle()
        brtc.setMicEnabled(isMicEnabled)
    }

    func playMedia() {
        guard let url = Bundle.main.url(forResource: "afro-pop", withExtension: "mp3") else {
            showErrorMessage("Media file not found in bundle")
            return
        }
        isPlayingMedia = true
        Task { @MainActor in
            do {
                try await brtc.publishFileAudio(url: url)
            } catch {
                isPlayingMedia = false
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    func stopMedia() {
        brtc.stopFileAudio()
        isPlayingMedia = false
    }

    func sendDtmf(_ tone: String) {
        brtc.sendDtmf(tone)
    }

    // MARK: - Simulate Incoming Call

    func simulateIncomingCall() {
        guard endpointId != nil else {
            showErrorMessage("Not connected to an endpoint yet")
            return
        }

        let delaySeconds = 3
        statusText = "Incoming call in \(delaySeconds)s..."

        // Schedule the ringing UI after a delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delaySeconds)) { [weak self] in
            guard let self, self.connectionState == .connected else { return }
            // Use the SDK's built-in CallKit reporting
            self.brtc.reportIncomingCall(callerName: "Incoming Call")
        }
    }

    // MARK: - CallKit Actions (called from delegate)

    /// Called when user taps Accept on the incoming call UI (CallKit or custom).
    func acceptIncomingCall() {
        guard connectionState == .ringing else { return }

        // Now create the Voice API call via the server
        guard let endpointId else {
            statusText = "Error: no endpoint"
            return
        }

        Task { @MainActor in
            // Answer through the SDK (unmutes pending stream, manages CallKit)
            try? await brtc.answerCall()

            // Tell the server to bridge the call
            do {
                guard let url = URL(string: "\(serverURL)/simulate-incoming-call") else {
                    showErrorMessage("Invalid server URL")
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = ["endpointId": endpointId, "delaySeconds": 0]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    showErrorMessage("Server returned error")
                    return
                }
            } catch {
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    /// Called when user taps Decline on the incoming call UI (CallKit or custom).
    func declineIncomingCall() {
        if connectionState == .ringing {
            Task { @MainActor in
                await brtc.rejectCall()
            }
            connectionState = .connected
            statusText = "Connected"

            let record = CallDetailRecord(
                id: UUID(),
                phoneNumber: "Incoming Call",
                direction: .inbound,
                timestamp: Date(),
                duration: 0
            )
            callHistory.addRecord(record)
        } else if connectionState == .inCall {
            hangup()
        }
    }

    // MARK: - Private: Stream Callbacks (for audio visualization)

    private func setupStreamCallbacks() {
        // Keep raw stream references for audio track lifecycle
        brtc.onStreamAvailable = { [weak self] stream in
            Task { @MainActor in
                self?.remoteStream = stream
            }
        }

        brtc.onStreamUnavailable = { [weak self] _ in
            Task { @MainActor in
                self?.remoteStream = nil
            }
        }

        brtc.onReady = { [weak self] metadata in
            Task { @MainActor in
                guard let self else { return }
                if let eid = metadata.endpointId {
                    self.endpointId = eid
                }
                self.statusText = "Ready\n\(metadata.endpointId ?? "")"
            }
        }
    }

    private func startCallTimer() {
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.callDuration += 1
            }
        }
        startStatsPolling()
        startAudioLevelMonitoring()
    }

    // MARK: - Stats Polling

    private func startStatsPolling() {
        statsTimer?.invalidate()
        previousStatsSnapshot = nil
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollStats()
            }
        }
    }

    private func stopStatsPolling() {
        statsTimer?.invalidate()
        statsTimer = nil
        callStats = nil
        previousStatsSnapshot = nil
        showStatsOverlay = false
    }

    // MARK: - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        localAudioLevels = []
        remoteAudioLevels = []

        let localAccumulator = AudioLevelAccumulator()
        let remoteAccumulator = AudioLevelAccumulator()

        brtc.onLocalAudioLevel = { [weak self] samples in
            localAccumulator.accumulate(samples)
            if let level = localAccumulator.getLevel() {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let displayLevel = self.isMicEnabled ? level : 0.0
                    self.localAudioLevels.append(displayLevel)
                    if self.localAudioLevels.count > self.waveformCapacity { self.localAudioLevels.removeFirst() }
                }
            }
        }

        brtc.onRemoteAudioLevel = { [weak self] samples in
            remoteAccumulator.accumulate(samples)
            if let level = remoteAccumulator.getLevel() {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.remoteAudioLevels.append(level)
                    if self.remoteAudioLevels.count > self.waveformCapacity { self.remoteAudioLevels.removeFirst() }
                }
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        brtc.onLocalAudioLevel = nil
        brtc.onRemoteAudioLevel = nil
        localAudioLevels = []
        remoteAudioLevels = []
    }

    private func pollStats() {
        brtc.getCallStats(previousSnapshot: previousStatsSnapshot) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                self.callStats = snapshot
                self.previousStatsSnapshot = snapshot
            }
        }
    }

    private func recordIncomingCall(phoneNumber: String) {
        let record = CallDetailRecord(
            id: UUID(),
            phoneNumber: phoneNumber,
            direction: .inbound,
            timestamp: Date(),
            duration: 0
        )
        callHistory.addRecord(record)
        activeCallRecordId = record.id
    }

    /// Save the final call duration to the active call record.
    private func finalizeCallRecord() {
        guard let id = activeCallRecordId else { return }
        callHistory.updateDuration(id: id, duration: callDuration)
        activeCallRecordId = nil
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    func formatBitrate(_ bps: Double) -> String {
        if bps > 1_000_000 {
            return String(format: "%.1f Mbps", bps / 1_000_000)
        } else if bps > 1_000 {
            return String(format: "%.0f kbps", bps / 1_000)
        } else if bps > 0 {
            return String(format: "%.0f bps", bps)
        }
        return "---"
    }
}

// MARK: - BandwidthRTCCallDelegate

extension CallViewModel: BandwidthRTCCallDelegate {
    @MainActor
    func bandwidthRTC(_ client: BandwidthRTCClient, callDidChangeState state: CallState, info: CallInfo) {
        switch state {
        case .ringing:
            connectionState = .ringing

        case .connecting:
            statusText = "Connecting..."

        case .active:
            connectionState = .inCall
            statusText = info.direction == .inbound ? "Incoming call" : "In call"
            if callTimer == nil {
                startCallTimer()
            }

        case .ended:
            finalizeCallRecord()
            callTimer?.invalidate()
            callTimer = nil
            callDuration = 0
            stopStatsPolling()
            stopAudioLevelMonitoring()
            connectionState = .connected
            statusText = "Call ended"
            remoteStream = nil

        case .idle:
            break
        }
    }

    @MainActor
    func bandwidthRTC(_ client: BandwidthRTCClient, didReceiveIncomingCall info: CallInfo) {
        recordIncomingCall(phoneNumber: info.remoteParty ?? "Incoming Call")
    }

    @MainActor
    func bandwidthRTC(_ client: BandwidthRTCClient, callDidFailWithError error: Error, info: CallInfo?) {
        showErrorMessage(error.localizedDescription)
    }
}

// MARK: - Audio Level Accumulator

private final class AudioLevelAccumulator {
    private var sumSq: Float = 0
    private var frameCount = 0
    private let lock = NSLock()

    func accumulate(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        for s in samples {
            sumSq += s * s
        }
        frameCount += samples.count
    }

    func getLevel() -> Float? {
        lock.lock()
        defer { lock.unlock() }

        guard frameCount >= 9600 else { return nil }

        let rms = (sumSq / Float(frameCount)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        let level = Float(max(0.0, min(1.0, (db + 70.0) / 70.0)))

        sumSq = 0
        frameCount = 0

        return level
    }
}
