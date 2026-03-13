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

final class CallViewModel: ObservableObject {
    // MARK: - UI State

    @Published var connectionState: ConnectionState = .disconnected
    @Published var serverURL: String = "http://localhost:3000"
    @Published var phoneNumber: String = ""
    @Published var isMicEnabled: Bool = true
    @Published var isSpeakerEnabled: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showDialpad: Bool = false
    @Published var statusText: String = ""
    @Published var callDuration: TimeInterval = 0
    @Published var callStats: CallStatsSnapshot?
    @Published var showStatsOverlay: Bool = false

    // MARK: - Audio Waveform

    /// Rolling buffer of normalized (0–1) mic amplitude samples for the outgoing audio waveform.
    @Published var localAudioLevels: [Float] = []
    /// Rolling buffer of normalized (0–1) remote audio level samples for the incoming audio waveform.
    @Published var remoteAudioLevels: [Float] = []

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
    private let callKitManager = CallKitManager()
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
    /// Holds the incoming stream until the user answers via CallKit.
    private var pendingIncomingStream: RtcStream?

    init() {
        setupCallbacks()
        setupCallKitCallbacks()
    }

    // MARK: - Actions

    func connect() {
        guard connectionState == .disconnected else { return }
        connectionState = .connecting
        statusText = "Fetching token..."

        Task { @MainActor in
            do {
                // Request microphone permission up-front before WebRTC setup.
                // This ensures the audio session can properly activate for
                // playback + recording (iOS 17+ uses AVAudioApplication).
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

                // Prepare CallKit audio session ownership before WebRTC initializes.
                // Must happen after mic permission is granted and before brtc.connect().
                callKitManager.prepareAudioSession()

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
        callKitManager.reportCallEnded(reason: .remoteEnded)
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
        pendingIncomingStream = nil
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
                    // useManualAudio=true means WebRTC won't start audio on its own.
                    // For outbound calls that bypass CallKit, enable it explicitly here.
                    RTCAudioSession.sharedInstance().isAudioEnabled = true
                    statusText = "Ringing..."
                    // Timer and waveform start when the remote party answers (onStreamAvailable).
                } else {
                    statusText = "Call not accepted"
                }
            } catch {
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    func hangup() {
        finalizeCallRecord()
        callTimer?.invalidate()
        callTimer = nil
        callDuration = 0
        stopStatsPolling()
        stopAudioLevelMonitoring()
        callKitManager.reportCallEnded(reason: .remoteEnded)

        Task { @MainActor in
            if !phoneNumber.isEmpty {
                do {
                    _ = try await brtc.hangupConnection(
                        endpoint: e164PhoneNumber,
                        type: .phoneNumber
                    )
                } catch {
                    // Ignore hangup errors
                }
            }
            connectionState = .connected
            statusText = "Connected"
            remoteStream = nil
            pendingIncomingStream = nil
        }
    }

    func toggleMic() {
        isMicEnabled.toggle()
        brtc.setMicEnabled(isMicEnabled)
    }

    func toggleSpeaker() {
        isSpeakerEnabled.toggle()
        callKitManager.setSpeaker(isSpeakerEnabled)
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
        // The actual Voice API call is NOT created yet — it starts when the user taps Accept.
        // On a real device, CallKit shows the native iOS call screen (triggered by a
        // PushKit VoIP push in production). In the simulator, CallKit is not supported.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delaySeconds)) { [weak self] in
            guard let self, self.connectionState == .connected else { return }

            self.connectionState = .ringing

            #if !targetEnvironment(simulator)
            self.callKitManager.reportIncomingCall(callerName: "Incoming Call") { error in
                if let error {
                    Task { @MainActor in
                        self.connectionState = .connected
                        self.statusText = "CallKit error: \(error.localizedDescription)"
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Private

    private func setupCallbacks() {
        brtc.onStreamAvailable = { [weak self] stream in
            Task { @MainActor in
                guard let self else { return }
                // Retain the remote stream so its audio track isn't deallocated
                self.remoteStream = stream

                if self.connectionState == .ringing {
                    // Simulated incoming call: CallKit / our ringing UI is already showing.
                    // Hold the stream and mute audio until the user taps Accept.
                    self.pendingIncomingStream = stream
                    stream.mediaStream.audioTracks.forEach { $0.isEnabled = false }
                } else if self.connectionState == .connected {
                    // Real incoming PSTN call — the server already bridged via
                    // <Connect><Endpoint>, so audio is flowing. Auto-answer
                    // and transition directly to in-call state.
                    self.connectionState = .inCall
                    self.statusText = "Incoming call"
                    self.recordIncomingCall(phoneNumber: "Incoming Call")
                    self.startCallTimer()
                } else if self.connectionState == .inCall {
                    // Stream arrived after user accepted (simulated incoming call) or during
                    // an outbound call. Start the timer if not already running.
                    if self.statusText == "Connecting..." {
                        self.statusText = "Incoming call"
                    }
                    if self.callTimer == nil {
                        self.startCallTimer()
                    }
                }
            }
        }

        brtc.onStreamUnavailable = { [weak self] streamId in
            Task { @MainActor in
                guard let self else { return }
                self.remoteStream = nil
                self.pendingIncomingStream = nil

                if self.connectionState == .ringing {
                    // Don't dismiss CallKit here — the Voice API bridge can cause
                    // transient stream unavailable events during setup. If the call
                    // truly failed, onRemoteDisconnected will fire and handle it.
                } else if self.connectionState == .inCall {
                    // Remote side hung up during active call
                    self.finalizeCallRecord()
                    self.callKitManager.reportCallEnded(reason: .remoteEnded)
                    self.callTimer?.invalidate()
                    self.callTimer = nil
                    self.callDuration = 0
                    self.stopStatsPolling()
                    self.stopAudioLevelMonitoring()
                    self.connectionState = .connected
                    self.statusText = "Call ended"
                } else {
                    self.statusText = "Remote stream ended"
                }
            }
        }

        brtc.onRemoteDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.connectionState == .ringing {
                    self.callKitManager.reportCallEnded(reason: .remoteEnded)
                    self.pendingIncomingStream = nil
                    self.connectionState = .connected
                    self.statusText = "Missed call"
                } else if self.connectionState == .inCall {
                    self.finalizeCallRecord()
                    self.callKitManager.reportCallEnded(reason: .remoteEnded)
                    self.callTimer?.invalidate()
                    self.callTimer = nil
                    self.callDuration = 0
                    self.stopStatsPolling()
                    self.stopAudioLevelMonitoring()
                    self.connectionState = .connected
                    self.statusText = "Call ended"
                    self.remoteStream = nil
                }
            }
        }

        brtc.onReady = { [weak self] metadata in
            Task { @MainActor in
                guard let self else { return }
                // Capture endpoint ID (redundant with TokenService, but ensures we have it)
                if let eid = metadata.endpointId {
                    self.endpointId = eid
                }
                self.statusText = "Ready\n\(metadata.endpointId ?? "")"
            }
        }
    }

    private func setupCallKitCallbacks() {
        callKitManager.onCallAnswered = { [weak self] uuid in
            Task { @MainActor in
                self?.acceptIncomingCall()
            }
        }

        callKitManager.onCallEnded = { [weak self] uuid in
            Task { @MainActor in
                self?.declineIncomingCall()
            }
        }
    }

    /// Called when user taps Accept on the incoming call UI (our custom UI or CallKit).
    func acceptIncomingCall() {
        guard connectionState == .ringing else { return }
        connectionState = .inCall
        statusText = "Connecting..."
        callDuration = 0

        recordIncomingCall(phoneNumber: "Incoming Call")

        // Now create the Voice API call — TTS starts fresh from the beginning.
        // The server creates a call from BW_FROM_NUMBER to BW_FROM_NUMBER.
        // B-leg answers with TTS before bridging.
        // A-leg bridges to the WebRTC endpoint via <Connect><Endpoint>.
        // When the bridge is established, onStreamAvailable fires and audio flows.
        guard let endpointId else {
            statusText = "Error: no endpoint"
            return
        }

        Task { @MainActor in
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

    /// Called when user taps Decline on the incoming call UI (our custom UI or CallKit).
    func declineIncomingCall() {
        if connectionState == .ringing {
            // User declined before answering — record as missed call
            callKitManager.reportCallEnded(reason: .declinedElsewhere)
            pendingIncomingStream = nil
            remoteStream = nil
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
            // User ended an active call via CallKit (e.g. lock screen End button)
            hangup()
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

        // Thread-safe accumulators for audio level calculations
        let localAccumulator = AudioLevelAccumulator()
        let remoteAccumulator = AudioLevelAccumulator()

        brtc.onLocalAudioLevel = { [weak self] samples in
            localAccumulator.accumulate(samples)
            if let level = localAccumulator.getLevel() {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // When mic is muted, show 0 levels (flat waveform)
                    let displayLevel = self.isMicEnabled ? level : 0.0
                    self.localAudioLevels.append(displayLevel)
                    if self.localAudioLevels.count > self.waveformCapacity { self.localAudioLevels.removeFirst() }
                }
            }
        }

        brtc.onRemoteAudioLevel = { [weak self] samples in
            remoteAccumulator.accumulate(samples)
            if let level = remoteAccumulator.getLevel() {
                if remoteAccumulator.logThisWindow() {
                    let (rms, db) = remoteAccumulator.getStats()
                    print("[BRTC] remote audio: rms=\(String(format: "%.5f", rms)) dB=\(String(format: "%.1f", db)) level=\(String(format: "%.3f", level))")
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.remoteAudioLevels.append(level)
                    if self.remoteAudioLevels.count > self.waveformCapacity { self.remoteAudioLevels.removeFirst() }
                }
            }
        }
        print("[BRTC] remote audio monitoring started")
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

// MARK: - Audio Level Accumulator

private final class AudioLevelAccumulator {
    private var sumSq: Float = 0
    private var frameCount = 0
    private var windowCount = 0
    private let lock = NSLock()
    private var callbackFired = false

    func accumulate(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }

        if !callbackFired {
            callbackFired = true
            let maxAmp = samples.map { abs($0) }.max() ?? 0
            print("[BRTC] audio callback FIRST FIRE: samples=\(samples.count) maxAmp=\(String(format: "%.6f", maxAmp))")
        }

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
        windowCount += 1

        return level
    }

    func getStats() -> (rms: Float, db: Float) {
        lock.lock()
        defer { lock.unlock() }

        let rms = (sumSq / Float(max(1, frameCount))).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        return (rms, db)
    }

    func logThisWindow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return windowCount % 5 == 0
    }
}
