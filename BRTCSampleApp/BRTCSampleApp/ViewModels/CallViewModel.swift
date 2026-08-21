import AVFoundation
import SwiftUI
import UIKit
import BandwidthRTC

/// Sentinel "to" value that signals a PlayAudio request rather than a real
/// endpoint-to-endpoint bridge. The gateway responds with a <PlayAudio> BXML
/// verb when it sees this dummy ENDPOINT target.
private let playAudioTarget = "playAudio"

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
    @Published var dtmfDuration: Int = 100
    @Published var statusText: String = ""
    @Published var callDuration: TimeInterval = 0
    @Published var callStats: CallStatsSnapshot?
    @Published var showStatsOverlay: Bool = false
    @Published var isPlayAudioCall: Bool = false

    // MARK: - Audio Waveform

    @Published var localAudioLevels: [Float] = []
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

    /// Whether the current phone number input is valid for placing a call.
    var isPhoneNumberValid: Bool {
        let digits = phoneNumber.filter { $0.isNumber }
        return digits.count >= 10
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

    private let brtc = BandwidthRTCClient()
    private let tokenService = TokenService()
    private let callKitManager = CallKitManager()
    private var localStream: RtcStream?
    private var remoteStream: RtcStream?
    private var callTimer: Timer?
    private var statsTimer: Timer?
    private var previousStatsSnapshot: CallStatsSnapshot?
    private let waveformCapacity = 50
    private var activeCallRecordId: UUID?
    private var endpointId: String?
    @Published private(set) var pendingIncomingStream: RtcStream?
    private var callStatusPollTimer: Timer?

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

                callKitManager.prepareAudioSession()

                // Connect with autoAccept: false to allow manual accept/decline of inbound calls
                let options = RtcOptions(autoAccept: false)
                try await brtc.connect(authParams: RtcAuthParams(endpointToken: token), options: options)

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
        guard isPhoneNumberValid else { return }

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
                    startCallStatusPolling()
                    // Timer and waveform start when the remote party answers (onStreamAvailable).
                } else {
                    statusText = "Call not accepted"
                }
            } catch {
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    /// Dials the demo "Play Audio" destination — a dummy ENDPOINT target with
    /// no bridge peer that the gateway answers with a <PlayAudio> BXML verb.
    func playAudio() {
        isPlayAudioCall = true
        connectionState = .inCall
        statusText = "Calling Play Audio..."

        let record = CallDetailRecord(
            id: UUID(),
            phoneNumber: "Play Audio",
            direction: .outbound,
            timestamp: Date(),
            duration: 0
        )
        callHistory.addRecord(record)
        activeCallRecordId = record.id

        Task { @MainActor in
            do {
                let result = try await brtc.requestOutboundConnection(
                    id: playAudioTarget,
                    type: .endpoint
                )
                if result.accepted {
                    RTCAudioSession.sharedInstance().isAudioEnabled = true
                    statusText = "Ringing..."
                } else {
                    isPlayAudioCall = false
                    statusText = "Call not accepted"
                }
            } catch {
                isPlayAudioCall = false
                showErrorMessage(error.localizedDescription)
            }
        }
    }

    func hangup() {
        let wasPlayAudioCall = isPlayAudioCall
        isPlayAudioCall = false
        finalizeCallRecord()
        callTimer?.invalidate()
        callTimer = nil
        callDuration = 0
        stopStatsPolling()
        stopAudioLevelMonitoring()
        stopCallStatusPolling()
        callKitManager.reportCallEnded(reason: .remoteEnded)

        Task { @MainActor in
            if wasPlayAudioCall {
                do {
                    _ = try await brtc.hangupConnection(endpoint: playAudioTarget, type: .endpoint)
                } catch {
                    print("[CallViewModel] Hangup failed: \(error)")
                }
            } else if !phoneNumber.isEmpty {
                do {
                    _ = try await brtc.hangupConnection(
                        endpoint: e164PhoneNumber,
                        type: .phoneNumber
                    )
                } catch {
                    print("[CallViewModel] Hangup failed: \(error)")
                }
            }

            // Notify backend to terminate the PSTN leg (Play Audio has no PSTN leg)
            if !wasPlayAudioCall, let eid = endpointId {
                do {
                    try await tokenService.hangupCall(serverURL: serverURL, endpointId: eid)
                    print("[CallViewModel] Backend hangup succeeded")
                } catch {
                    print("[CallViewModel] Backend hangup failed: \(error)")
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
        brtc.sendDtmf(tone, duration: dtmfDuration)
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
                if self.connectionState == .connecting || self.connectionState == .disconnected {
                    print("[CallViewModel] Stream arrived in \(self.connectionState) state — ignoring")
                    return
                }

                self.remoteStream = stream

                // Check if this inbound call was auto-accepted by the gateway
                let isAutoAccepted = stream.autoAccepted ?? true

                if self.connectionState == .ringing {
                    // User already initiated a manual accept/decline flow
                    self.pendingIncomingStream = stream
                    if !isAutoAccepted {
                        // Audio gate is closed — keep audio tracks disabled
                        stream.mediaStream.audioTracks.forEach { $0.isEnabled = false }
                    }
                } else if self.connectionState == .connected {
                    if !isAutoAccepted {
                        // This is a parked inbound call — transition to ringing and wait for user action
                        self.pendingIncomingStream = stream
                        stream.mediaStream.audioTracks.forEach { $0.isEnabled = false }
                        self.connectionState = .ringing
                        self.statusText = "Incoming call"
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
                    } else {
                        // Auto-accepted inbound call — proceed to in-call state
                        self.connectionState = .inCall
                        self.statusText = "Incoming call"
                        self.recordIncomingCall(phoneNumber: "Incoming Call")
                        self.startCallTimer()
                    }
                } else if self.connectionState == .inCall {
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

        Task { @MainActor in
            do {
                // Call the SDK to open the audio gate on the parked inbound call
                try await brtc.acceptStream()

                // Enable audio playback for the pending stream
                if let stream = pendingIncomingStream {
                    stream.mediaStream.audioTracks.forEach { $0.isEnabled = true }
                }

                startCallTimer()
            } catch {
                showErrorMessage(error.localizedDescription)
                connectionState = .ringing
                statusText = "Accept failed"
            }
        }
    }

    /// Called when user taps Decline on the incoming call UI (our custom UI or CallKit).
    func declineIncomingCall() {
        if connectionState == .ringing {
            // User declined before answering — tell the SDK to reject the call
            Task { @MainActor in
                do {
                    try await brtc.declineStream()
                } catch {
                    print("[CallViewModel] declineStream failed: \(error)")
                }

                // Clean up local state and record as missed call
                self.callKitManager.reportCallEnded(reason: .declinedElsewhere)
                self.pendingIncomingStream = nil
                self.remoteStream = nil
                self.connectionState = .connected
                self.statusText = "Connected"

                let record = CallDetailRecord(
                    id: UUID(),
                    phoneNumber: "Incoming Call",
                    direction: .inbound,
                    timestamp: Date(),
                    duration: 0
                )
                self.callHistory.addRecord(record)
            }
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

    // MARK: - Call Status Polling

    private func startCallStatusPolling() {
        stopCallStatusPolling()
        guard let eid = endpointId else { return }
        print("[CallViewModel] Starting call status polling for endpoint \(eid)")

        callStatusPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    let status = try await self.tokenService.getCallStatus(
                        serverURL: self.serverURL, endpointId: eid
                    )
                    print("[CallViewModel] Poll status: \(status.status) (cause: \(status.cause ?? "none"))")

                    if status.status == "disconnected" {
                        print("[CallViewModel] PSTN call rejected/disconnected — ending call locally")
                        self.stopCallStatusPolling()
                        self.hangup()
                    }
                } catch {
                    print("[CallViewModel] Poll error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopCallStatusPolling() {
        callStatusPollTimer?.invalidate()
        callStatusPollTimer = nil
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

// MARK: - Audio Level Accumulator

private final class AudioLevelAccumulator {
    private var sumSq: Float = 0
    private var frameCount = 0
    private var windowCount = 0
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
}
