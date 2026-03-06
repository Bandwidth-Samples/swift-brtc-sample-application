import AVFoundation
import CallKit
import WebRTC

/// Manages CallKit integration for native iOS incoming call UI.
///
/// When an incoming call is detected via BRTC, this class reports it to CallKit
/// so the system displays the native incoming call screen (even when backgrounded).
/// The `onCallAnswered` / `onCallEnded` closures communicate back to CallViewModel.
final class CallKitManager: NSObject, CXProviderDelegate {

    // MARK: - Callbacks (to CallViewModel)

    /// Called when the user taps Accept on the native call UI.
    var onCallAnswered: ((UUID) -> Void)?

    /// Called when the user taps Decline or End on the native call UI.
    var onCallEnded: ((UUID) -> Void)?

    // MARK: - State

    private(set) var activeCallUUID: UUID?

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
        provider.setDelegate(self, queue: nil) // nil = main queue
    }

    // MARK: - Report Incoming Call

    /// Show the native iOS incoming call screen.
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
                print("[CallKit] Failed to report incoming call: \(error)")
            }
            completion(error)
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

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // User tapped Accept on the native call UI
        onCallAnswered?(action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // User tapped Decline (before answering) or End (during call)
        let uuid = action.callUUID
        if uuid == activeCallUUID {
            onCallEnded?(uuid)
            activeCallUUID = nil
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Inform WebRTC that CallKit activated the audio session
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    }

    // MARK: - Manual Audio Session (non-CallKit outbound calls)

    /// Configures and activates the audio session for outbound calls that don't go
    /// through CallKit. Must be called after the call is established.
    func activateAudioSessionForOutboundCall() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            RTCAudioSession.sharedInstance().audioSessionDidActivate(session)
        } catch {
            print("[CallKit] Failed to activate audio session: \(error)")
        }
    }

    func deactivateAudioSessionForOutboundCall() {
        let session = AVAudioSession.sharedInstance()
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(session)
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[CallKit] Failed to deactivate audio session: \(error)")
        }
    }
}
