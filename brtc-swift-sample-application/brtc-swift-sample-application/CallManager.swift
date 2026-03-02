import Foundation
@preconcurrency import BandwidthWebRTC
import WebRTC
import Combine

class CallManager: ObservableObject {
    @Published var connectionState: String = "Disconnected"
    @Published var isInCall: Bool = false
    @Published var isMuted: Bool = false
    @Published var callDuration: TimeInterval = 0
    @Published var endpoint: Endpoint?
    @Published var remoteStreams: [RTCStream] = []
    
    var settings: SettingsManager
    
    private var rtc: RTCBandwidth!
    lazy var backendService: BackendService = {
        return BackendService(settings: settings)
    }()
    private var localStream: RTCStream?
    private var callTimer: Timer?
    
    init(settings: SettingsManager) {
        self.settings = settings
        print("CallManager initializing...")
        rtc = RTCBandwidth()
        print("RTCBandwidth initialized")
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
            
            // Extract gateway URL from JWT token
            let websocketUrl = extractGatewayUrl(from: endpoint.endpointToken) ?? "wss://gateway.pv.prod.global.aws.bandwidth.com/prod/gateway-service/api/v1/endpoints"
            print("Using WebSocket URL: \(websocketUrl)")
            
            let rtcAuth = RTCAuth(endpointToken: endpoint.endpointToken)
            let rtcOptions = RTCOptions(websocketUrl: websocketUrl, iceServers: [], iceTransportPolicy: .all)
            
            rtc.connect(rtcAuth: rtcAuth, rtcOptions: rtcOptions) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.connectionState = "Connected"
                        print("WebRTC connected successfully")
                    case .failure(let error):
                        self?.connectionState = "Connection Failed: \(error.localizedDescription)"
                        print("WebRTC connection failed: \(error)")
                        print("Error type: \(type(of: error))")
                        if let nsError = error as NSError? {
                            print("Error domain: \(nsError.domain)")
                            print("Error code: \(nsError.code)")
                            print("Error userInfo: \(nsError.userInfo)")
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.connectionState = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func extractGatewayUrl(from token: String) -> String? {
        // JWT format: header.payload.signature
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        
        // Decode the payload (base64url)
        var base64 = String(parts[1])
        // Convert base64url to base64
        base64 = base64.replacingOccurrences(of: "-", with: "+")
        base64 = base64.replacingOccurrences(of: "_", with: "/")
        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gatewayUrl = json["gatewayRegionalUri"] as? String else {
            return nil
        }
        
        print("Extracted gateway URL from token: \(gatewayUrl)")
        return gatewayUrl
    }
    
    func startCall(destination: String, type: EndpointType) async {
        guard connectionState == "Connected" else {
            print("Cannot start call: Not connected to WebRTC. Current state: \(connectionState)")
            DispatchQueue.main.async {
                self.connectionState = "Error: Not connected. Create endpoint first."
            }
            return
        }
        
        guard let _ = endpoint?.endpointId else {
            print("Cannot start call: No endpoint available")
            DispatchQueue.main.async {
                self.connectionState = "Error: No endpoint available"
            }
            return
        }

        do {
            // 1. Initiate call via SDK
            print("Requesting outbound connection to \(destination) type: \(type.rawValue)")
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                rtc.requestOutboundConnection(id: destination, type: type) { result in
                    switch result {
                    case .success(_):
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            print("Outbound connection requested successfully.")

            // 2. Publish local media stream
            rtc.publish(alias: destination) { [weak self] stream in
                DispatchQueue.main.async {
                    self?.localStream = stream
                    self?.isInCall = true
                    self?.startCallTimer() // Start timer when call is established
                    print("Local stream published.")
                }
            }
        } catch {
            print("Error initiating call: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.connectionState = "Call Failed: \(error.localizedDescription)"
            }
        }
    }
    
    func placePhoneCall(phoneNumber: String, endpointId: String) async {
        guard connectionState == "Connected" else {
            print("Cannot place call: Not connected to WebRTC. Current state: \(connectionState)")
            DispatchQueue.main.async {
                self.connectionState = "Error: Not connected. Create endpoint first."
            }
            return
        }
        
        guard let _ = endpoint?.endpointId else {
            print("Cannot place call: No endpoint available")
            DispatchQueue.main.async {
                self.connectionState = "Error: No endpoint available"
            }
            return
        }
        
        do {
            // Step 1: Place the call to the phone number via backend
            print("Placing call to \(phoneNumber) from endpoint \(endpointId)")
            try await backendService.placeCall(fromEndpointId: endpointId, toNumber: phoneNumber)
            print("Call placed successfully via backend.")
            
            // Step 2: Start the WebRTC connection to the endpoint
            print("Starting WebRTC connection to endpoint \(endpointId)")
            await startCall(destination: endpointId, type: .endpoint)
            
        } catch {
            print("Error placing phone call: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.connectionState = "Phone Call Failed: \(error.localizedDescription)"
            }
        }
    }
    
    func sendDTMF(key: String) {
        rtc.sendDtmf(tone: key)
        print("Sent DTMF: \(key)")
    }
    
    func toggleMute() {
        guard let audioTrack = localStream?.mediaStream.audioTracks.first else {
            print("No local audio track found to toggle mute.")
            return
        }
        audioTrack.isEnabled.toggle()
        DispatchQueue.main.async {
            self.isMuted = !audioTrack.isEnabled // Reflect the actual state of the audio track
            print("Audio track isEnabled: \(audioTrack.isEnabled), CallManager.isMuted: \(self.isMuted)")
        }
    }
    
    func endCall() {
        if let stream = localStream {
            rtc.unpublish(streamIds: [stream.mediaStream.streamId]) {
                print("Unpublished")
            }
        }
        self.isInCall = false
        stopCallTimer() // Stop timer when call ends
        self.callDuration = 0 // Reset duration
        // Also strictly we should probably delete the endpoint or disconnect, but for a soft hangup, unpublishing is often used in these samples.
        // Or we disconnect the session.
    }
    
    private func startCallTimer() {
        callTimer?.invalidate() // Invalidate any existing timer
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.callDuration += 1
            }
        }
    }
    
    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
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
