import AVFoundation
import BandwidthRTC
import CallKit
import os

/// Manages CallKit integration for native iOS incoming call UI.
///
/// When an incoming call is detected via BRTC, this class reports it to CallKit
/// so the system displays the native incoming call screen (even when backgrounded).
/// The `onCallAnswered` / `onCallEnded` closures communicate back to CallViewModel.
final class CallKitManager: NSObject, CXProviderDelegate {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BRTCSampleApp", category: "CallKit")

    /// The BRTC client to forward `AVAudioSession` activation state to. Set once, before
    /// `connect()` is called with `AudioProcessingOptions.manualAudioSessionActivation = true`.
    weak var brtc: BandwidthRTCClient?

    // MARK: - Callbacks (to CallViewModel)

    /// Called when the user taps Accept on the native call UI.
    var onCallAnswered: ((UUID) -> Void)?

    /// Called when the user taps Decline or End on the native call UI.
    var onCallEnded: ((UUID) -> Void)?

    /// Called when CallKit accepts the outbound CXStartCallAction.
    var onOutboundCallStarted: ((UUID) -> Void)?

    // MARK: - State

    private(set) var activeCallUUID: UUID?

    // MARK: - CallKit

    // Created lazily so constructing `CallKitManager` doesn't pay CXProvider's
    // first-time XPC registration cost (often several seconds on a fresh install)
    // on the main thread during CallViewModel's synchronous init.
    private lazy var provider: CXProvider = {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]

        let provider = CXProvider(configuration: config)
        provider.setDelegate(self, queue: nil)
        return provider
    }()
    private let callController = CXCallController()

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

        let cxHandle = CXHandle(type: .generic, value: handle)
        let action = CXStartCallAction(call: uuid, handle: cxHandle)
        action.isVideo = false

        let transaction = CXTransaction(action: action)
        callController.request(transaction) { error in
            if let error {
                Self.logger.error("CXStartCallAction failed: \(error)")
                self.activeCallUUID = nil
            }
        }
    }

    // MARK: - Report Call Ended (from app side)

    /// Tell CallKit a call ended (e.g. remote hangup or local hangup).
    func reportCallEnded(reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = activeCallUUID else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        activeCallUUID = nil
    }

    // MARK: - CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        activeCallUUID = nil
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
        }
        action.fulfill()
    }

    /// Whether the speaker override should be applied when the session activates.
    var speakerEnabled: Bool = false

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        brtc?.audioSessionDidActivate(audioSession)
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
        brtc?.audioSessionDidDeactivate(audioSession)
    }
}