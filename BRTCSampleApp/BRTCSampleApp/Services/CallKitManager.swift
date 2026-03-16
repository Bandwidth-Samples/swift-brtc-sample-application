import AVFoundation
import CallKit
import os
import WebRTC

/// Manages CallKit integration for native iOS incoming call UI.
///
/// When an incoming call is detected via BRTC, this class reports it to CallKit
/// so the system displays the native incoming call screen (even when backgrounded).
/// The `onCallAnswered` / `onCallEnded` closures communicate back to CallViewModel.
final class CallKitManager: NSObject, CXProviderDelegate {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BRTCSampleApp", category: "CallKit")

    // MARK: - Callbacks (to CallViewModel)

    /// Called when the user taps Accept on the native call UI.
    var onCallAnswered: ((UUID) -> Void)?

    /// Called when the user taps Decline or End on the native call UI.
    var onCallEnded: ((UUID) -> Void)?

    /// Called when CallKit accepts the outbound CXStartCallAction.
    var onOutboundCallStarted: ((UUID) -> Void)?

    // MARK: - State

    private(set) var activeCallUUID: UUID?
    private var isOutboundCall: Bool = false

    // MARK: - CallKit

    private let provider: CXProvider
    private let callController = CXCallController()

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]

        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    /// Call this once before the first BRTC connection is established.
    func prepareAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
        } catch {
            Self.logger.error("AVAudioSession config failed: \(error)")
        }

        RTCAudioSession.sharedInstance().useManualAudio = true
    }

    // MARK: - Report Incoming Call

    /// Show the native iOS incoming call screen with a branded caller name.
    func reportIncomingCall(
        callerName: String,
        completion: @escaping (Error?) -> Void
    ) {
        let uuid = UUID()
        activeCallUUID = uuid

        let update = CXCallUpdate()
        update.localizedCallerName = callerName
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                self.activeCallUUID = nil
                Self.logger.error("Failed to report incoming call: \(error)")
            }
            completion(error)
        }
    }

    // MARK: - Start Outbound Call

    /// Register an outbound call with CallKit for system UI integration.
    func startOutboundCall(handle: String) {
        let uuid = UUID()
        activeCallUUID = uuid
        isOutboundCall = true

        let cxHandle = CXHandle(type: .generic, value: handle)
        let action = CXStartCallAction(call: uuid, handle: cxHandle)
        action.isVideo = false

        let transaction = CXTransaction(action: action)
        callController.request(transaction) { error in
            if let error {
                Self.logger.error("CXStartCallAction failed: \(error)")
                self.activeCallUUID = nil
                self.isOutboundCall = false
            }
        }
    }

    // MARK: - Report Call Ended (from app side)

    /// Tell CallKit a call ended (e.g. remote hangup or local hangup).
    func reportCallEnded(reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = activeCallUUID else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        activeCallUUID = nil
        isOutboundCall = false
    }

    // MARK: - CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        activeCallUUID = nil
        isOutboundCall = false
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        action.fulfill()
        onOutboundCallStarted?(action.callUUID)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // User tapped Accept on the native call UI
        onCallAnswered?(action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let uuid = action.callUUID
        if uuid == activeCallUUID {
            onCallEnded?(uuid)
            activeCallUUID = nil
            isOutboundCall = false
        }
        action.fulfill()
    }

    /// Whether the speaker override should be applied when the session activates.
    var speakerEnabled: Bool = false

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        let rtcSession = RTCAudioSession.sharedInstance()

        if isOutboundCall {
            // For outbound calls, skip audioSessionDidActivate to avoid resetting the already-initialized engine
            rtcSession.isAudioEnabled = true
        } else {
            // For incoming calls, the engine needs full activation
            rtcSession.audioSessionDidActivate(audioSession)
            rtcSession.isAudioEnabled = true
        }

        applyOutputRoute()
    }

    func setSpeaker(_ enabled: Bool) {
        speakerEnabled = enabled
        applyOutputRoute()
    }

    private func applyOutputRoute() {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(speakerEnabled ? .speaker : .none)
        } catch {
            Self.logger.error("overrideOutputAudioPort failed: \(error)")
        }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    }
}