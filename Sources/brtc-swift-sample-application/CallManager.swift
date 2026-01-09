import Foundation
import BandwidthWebRTC
import WebRTC
import Combine

class CallManager: ObservableObject {
    @Published var connectionState: String = "Disconnected"
    @Published var isInCall: Bool = false
    @Published var endpoint: Endpoint?
    @Published var remoteStreams: [RTCStream] = []
    
    private let rtc = RTCBandwidth()
    private let backendService = BackendService()
    private var localStream: RTCStream?
    
    // Delegate to handle events if SDK supports it, otherwise rely on closure callbacks and state
    // Checking SDK source might be useful, but assuming closure based on CLI sample.
    // However, for incoming streams (remote participants), we usually need a delegate or a callback.
    // The CLI sample didn't handle incoming streams. I should check the SDK for `onStreamAvailable` equivalent.
    
    init() {
        // Set up delegate if applicable.
        rtc.delegate = self
    }
    
    func connect() async {
        DispatchQueue.main.async {
            self.connectionState = "Creating Endpoint..."
        }
        
        do {
            let endpoint = try await backendService.createEndpoint()
            DispatchQueue.main.async {
                self.endpoint = endpoint
                self.connectionState = "Connecting to WebRTC..."
            }
            
            let rtcAuth = RTCAuth(endpointToken: endpoint.endpointToken)
            let rtcOptions = RTCOptions(websocketUrl: "wss://device.webrtc.bandwidth.com", iceServers: [], iceTransportPolicy: .all)
            
            rtc.connect(rtcAuth: rtcAuth, rtcOptions: rtcOptions) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.connectionState = "Connected"
                    case .failure(let error):
                        self?.connectionState = "Connection Failed: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.connectionState = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    func startCall(phoneNumber: String) {
        guard connectionState == "Connected" else { return }
        
        // For a dialer, we publish our media to the session.
        // The backend logic (Browser Dialer) handles the "Outbound Call" request when it sees a new endpoint or via a specific API.
        // In the Browser sample, it calls `placeCall` on the backend.
        // Wait, the CLI sample had a `placeCall` method in `Interactive` that just published.
        // But the `server/index.ts` had a `/api/testCall` or similar.
        // The browser sample: `CallController.tsx` calls `backend.callPhone(number)`.
        
        // My `BackendService.swift` currently only has `createEndpoint`. I might need to add `placeCall` if the logic requires it.
        // But for "Bandwidth WebRTC", typically you publish media, and if the session is connected to a SIP URI (via BXML `Transfer`), it works.
        // The browser sample server handled `outboundConnectionRequest` callback.
        // So simply creating an endpoint and connecting might not be enough to dial OUT to a PSTN number unless the server logic is set up to bridge them.
        // The Browser Dialer server listens for `outboundConnectionRequest`.
        // To trigger that, the client might need to request it.
        // Actually, in the browser sample, `MediaPlayer.tsx` or `CallController.tsx` creates the call.
        // `server/index.ts`: `app.post('/api/endpoint', ...)` creates endpoint.
        // The *client* places the call?
        // `server/index.ts`: `app.post('/api/callbacks/endpoints/status')` -> case `outboundConnectionRequest`.
        // So the client must send an `outboundConnectionRequest`? No, the *Server* receives it from Bandwidth when the client tries to call?
        // Or the client calls a backend API to initiate the call.
        // `server/index.ts` has `app.post('/api/testCall')`.
        
        // **CRITICAL**: The browser sample usually involves the user typing a number, hitting "Call", and the App calling the *Backend* to initiate the call via `callsApi.createCall`.
        
        // I should probably add `placeCall` to `BackendService`.
        
        rtc.publish(alias: phoneNumber) { [weak self] stream in
            DispatchQueue.main.async {
                self?.localStream = stream
                self?.isInCall = true
            }
        }
    }
    
    func endCall() {
        if let stream = localStream {
            rtc.unpublish(streamIds: [stream.mediaStream.streamId]) {
                print("Unpublished")
            }
        }
        self.isInCall = false
        // Also strictly we should probably delete the endpoint or disconnect, but for a soft hangup, unpublishing is often used in these samples.
        // Or we disconnect the session.
    }
    
    func disconnect() {
        rtc.disconnect()
        if let endpointId = endpoint?.endpointId {
            Task {
                try? await backendService.deleteEndpoint(endpointId: endpointId)
            }
        }
        connectionState = "Disconnected"
        endpoint = nil
    }
}

extension CallManager: RTCBandwidthDelegate {
    func bandwidth(_ bandwidth: RTCBandwidth, streamAvailable stream: RTCStream) {
        DispatchQueue.main.async {
            self.remoteStreams.append(stream)
        }
    }
    
    func bandwidth(_ bandwidth: RTCBandwidth, streamUnavailable stream: RTCStream) {
        DispatchQueue.main.async {
            self.remoteStreams.removeAll { $0.mediaStream.streamId == stream.mediaStream.streamId }
        }
    }
}
