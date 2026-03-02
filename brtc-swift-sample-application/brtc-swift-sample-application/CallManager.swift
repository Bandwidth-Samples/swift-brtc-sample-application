import Foundation
@preconcurrency import BandwidthWebRTC
import WebRTC
import Combine

class CallManager: ObservableObject {
    @Published var connectionState: String = "Disconnected"
    @Published var isInCall: Bool = false
    @Published var isMuted: Bool = false
    @Published var callDuration: TimeInterval = 0
    @Published var remoteStreams: [RTCStream] = []

    var settings: SettingsManager
    private(set) var endpoint: Endpoint?

    private var rtc: RTCBandwidth
    lazy var backendService: BackendService = { BackendService(settings: settings) }()
    private var localStream: RTCStream?
    private var callTimer: Timer?

    init(settings: SettingsManager) {
        self.settings = settings
        self.rtc = RTCBandwidth()

        rtc.onStreamAvailable { [weak self] stream in
            DispatchQueue.main.async {
                self?.remoteStreams.append(stream)
            }
        }

        rtc.onStreamUnavailable { [weak self] stream in
            DispatchQueue.main.async {
                self?.remoteStreams.removeAll { $0.mediaStream.streamId == stream.mediaStream.streamId }
            }
        }

        rtc.onReady { _ in
            print("RTCBandwidth is ready")
        }
    }

    // MARK: - Connection

    /// Creates an endpoint and connects to the WebRTC signaling server.
    /// After this completes, the peer connections are established and the SDK is ready to publish.
    private func connect() async throws {
        await setState("Creating Endpoint...")

        let endpoint = try await backendService.createEndpoint()
        await MainActor.run {
            self.endpoint = endpoint
            self.connectionState = "Connecting to WebRTC..."
        }

        let websocketUrl = extractGatewayUrl(from: endpoint.endpointToken)
            ?? "wss://us-east-2.gateway.pv.prod.global.aws.bandwidth.com/prod/gateway-service/api/v1/endpoints"
        print("Connecting to: \(websocketUrl)")

        let rtcAuth = RTCAuth(endpointToken: endpoint.endpointToken)
        let rtcOptions = RTCOptions(websocketUrl: websocketUrl, iceServers: [], iceTransportPolicy: .all)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            rtc.connect(rtcAuth: rtcAuth, rtcOptions: rtcOptions) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        await setState("Connected")
        print("WebRTC connected — endpoint: \(endpoint.endpointId)")
    }

    // MARK: - Outbound Calls

    /// Place a WebRTC-to-WebRTC or WebRTC-to-CallId call.
    func call(destination: String, type: EndpointType) async {
        do {
            if connectionState != "Connected" {
                try await connect()
            }

            await setState("Calling \(destination)...")

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                rtc.requestOutboundConnection(id: destination, type: type) { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            await publishLocalMedia(alias: destination)
        } catch {
            await setState("Error: \(error.localizedDescription)")
            print("call(destination:type:) failed: \(error)")
        }
    }

    /// Place an outbound call to a PSTN phone number.
    /// The backend places the PSTN call and bridges it to the WebRTC endpoint;
    /// no requestOutboundConnection is needed — just publish local media.
    func callPhoneNumber(_ phoneNumber: String) async {
        do {
            if connectionState != "Connected" {
                try await connect()
            }

            guard let endpointId = endpoint?.endpointId else {
                await setState("Error: No endpoint available")
                return
            }

            await setState("Placing call to \(phoneNumber)...")
            try await backendService.placeCall(fromEndpointId: endpointId, toNumber: phoneNumber)
            print("PSTN call placed from endpoint \(endpointId) to \(phoneNumber)")

            await publishLocalMedia(alias: phoneNumber)
        } catch {
            await setState("Error: \(error.localizedDescription)")
            print("callPhoneNumber(_:) failed: \(error)")
        }
    }

    // MARK: - Call Controls

    func toggleMute() {
        isMuted.toggle()
        rtc.setMicEnabled(!isMuted)
        print("Mic enabled: \(!isMuted)")
    }

    func sendDTMF(key: String) {
        rtc.sendDtmf(tone: key)
        print("Sent DTMF: \(key)")
    }

    func endCall() {
        if let stream = localStream {
            rtc.unpublish(streamIds: [stream.mediaStream.streamId]) {
                print("Local stream unpublished")
            }
            localStream = nil
        }

        rtc.disconnect()

        if let endpointId = endpoint?.endpointId {
            Task { try? await backendService.deleteEndpoint(endpointId: endpointId) }
        }

        stopCallTimer()

        DispatchQueue.main.async {
            self.isInCall = false
            self.isMuted = false
            self.callDuration = 0
            self.remoteStreams = []
            self.endpoint = nil
            self.connectionState = "Disconnected"
        }
    }

    // MARK: - Private Helpers

    private func publishLocalMedia(alias: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            rtc.publish(alias: alias) { [weak self] stream in
                DispatchQueue.main.async {
                    self?.localStream = stream
                    self?.isInCall = true
                    self?.startCallTimer()
                    print("Local stream published — stream: \(stream.mediaStream.streamId)")
                }
                continuation.resume()
            }
        }
    }

    private func extractGatewayUrl(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["gatewayRegionalUri"] as? String else { return nil }

        print("Gateway URL from token: \(url)")
        return url
    }

    @MainActor
    private func setState(_ state: String) {
        connectionState = state
    }

    private func startCallTimer() {
        callTimer?.invalidate()
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.callDuration += 1 }
        }
    }

    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }
}
