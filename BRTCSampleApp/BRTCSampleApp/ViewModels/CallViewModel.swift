import AVFoundation
import SwiftUI
import UIKit
import BandwidthBRTC

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case ringing   // CallKit incoming call UI shown, awaiting answer/decline
    case inCall
}

@Observable
final class CallViewModel {
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

    private let brtc = BandwidthRTC(logLevel: .debug)
    private let tokenService = TokenService()
    private let callKitManager = CallKitManager()
    private var localStream: RtcStream?
    /// Strong reference to the remote stream so the audio track isn't released.
    private var remoteStream: RtcStream?
    private var callTimer: Timer?
    private var statsTimer: Timer?
    private var previousStatsSnapshot: CallStatsSnapshot?
    private var audioLevelTimer: Timer?
    private let waveformCapacity = 50
    /// Tracks the active call record so we can update its duration when the call ends.
    private var activeCallRecordId: UUID?
    /// Our BRTC endpoint ID (for simulate-bank-call API).
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
        brtc.disconnect()
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
        let record = CallRecord(
            id: UUID(),
            phoneNumber: formattedPhoneNumber,
            e164Number: e164PhoneNumber,
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
                    callKitManager.activateAudioSessionForOutboundCall()
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
        stopMedia()
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

    // MARK: - Simulate Bank Call

    func simulateBankCall() {
        guard endpointId != nil else {
            showErrorMessage("Not connected to an endpoint yet")
            return
        }

        let delaySeconds = 3
        statusText = "Acme Bank calling in \(delaySeconds)s..."

        // Schedule the ringing UI after a delay (simulates the bank deciding to call).
        // The actual Voice API call is NOT created yet — it starts when the user taps Accept.
        // On a real device, CallKit shows the native iOS call screen (triggered by a
        // PushKit VoIP push in production). In the simulator, CallKit is not supported.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delaySeconds)) { [weak self] in
            guard let self, self.connectionState == .connected else { return }

            self.connectionState = .ringing

            #if !targetEnvironment(simulator)
            self.callKitManager.reportIncomingCall(callerName: "Acme Bank") { error in
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
                    // Simulated bank call: CallKit / our ringing UI is already showing.
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
                    // Stream arrived after user accepted (simulated bank call) or during
                    // an outbound call. Audio is enabled — update status to show connected.
                    if self.statusText == "Connecting..." {
                        self.statusText = "Acme Bank"
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

        recordIncomingCall(phoneNumber: "Acme Bank")

        // Now create the Voice API call — TTS starts fresh from the beginning.
        // The server creates a call from BW_FROM_NUMBER to BW_FROM_NUMBER.
        // B-leg answers with TTS ("Hello, this is Acme Bank...").
        // A-leg bridges to the WebRTC endpoint via <Connect><Endpoint>.
        // When the bridge is established, onStreamAvailable fires and audio flows.
        guard let endpointId else {
            statusText = "Error: no endpoint"
            return
        }

        Task { @MainActor in
            do {
                guard let url = URL(string: "\(serverURL)/simulate-bank-call") else {
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

            let record = CallRecord(
                id: UUID(),
                phoneNumber: "Acme Bank",
                e164Number: "",
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
        // Accumulate RMS over 200 ms windows (9600 frames at 48 kHz).
        // sumSq and frameCount are closure-local to avoid cross-thread access to @Observable properties.
        var sumSq: Float = 0
        var frameCount = 0
        brtc.onLocalAudioLevel = { [weak self] samples in
            for s in samples { sumSq += s * s }
            frameCount += samples.count
            if frameCount >= 9600 {
                let rms = (sumSq / Float(frameCount)).squareRoot()
                let db = 20 * log10(max(rms, 1e-7))
                let level = Float(max(0.0, min(1.0, (db + 70.0) / 70.0)))
                sumSq = 0
                frameCount = 0
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.localAudioLevels.append(level)
                    if self.localAudioLevels.count > self.waveformCapacity { self.localAudioLevels.removeFirst() }
                }
            }
        }
        // Poll remote audio level at 200 ms for a smooth waveform.
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.sampleRemoteAudioLevel()
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        brtc.onLocalAudioLevel = nil
        localAudioLevels = []
        remoteAudioLevels = []
    }

    private func sampleRemoteAudioLevel() {
        brtc.getCallStats(previousSnapshot: nil) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                let level = Float(max(0.0, min(1.0, snapshot.audioLevel)))
                self.remoteAudioLevels.append(level)
                if self.remoteAudioLevels.count > self.waveformCapacity {
                    self.remoteAudioLevels.removeFirst()
                }
            }
        }
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
        let record = CallRecord(
            id: UUID(),
            phoneNumber: phoneNumber,
            e164Number: "",
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
}
