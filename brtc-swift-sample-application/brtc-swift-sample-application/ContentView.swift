import BandwidthWebRTC
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var callManager: CallManager
    @State private var showingSettingsSheet = false

    @State private var destinationId: String = ""
    @State private var selectedEndpointType: BandwidthWebRTC.EndpointType =
        .phoneNumber
    @State private var createdEndpointId: String? = nil
    @FocusState private var isInputFocused: Bool

    let endpointTypes: [BandwidthWebRTC.EndpointType] = [
        .phoneNumber, .endpoint, .callId,
    ]

    init(settings: SettingsManager) {
        print("ContentView initializing")
        self._callManager = StateObject(wrappedValue: CallManager(settings: settings))
    }

    var body: some View {
        NavigationView {  // Keep NavigationView for iOS
            ZStack {
                if callManager.isInCall {
                    ActiveCallView(callManager: callManager)
                        .transition(.move(edge: .bottom))
                } else {
                    GeometryReader { geometry in
                        VStack {
                            // Endpoint creation and deletion buttons
                            Spacer(minLength: geometry.size.height * 0.2)
                            
                            HStack(spacing: 20) {
                                Button("Create Endpoint & Connect") {
                                    Task {
                                        do {
                                            // First create the endpoint
                                            let endpoint = try await callManager.backendService.createEndpoint()
                                            createdEndpointId = endpoint.endpointId
                                            print("Created Endpoint: \(endpoint.endpointId)")
                                            
                                            // Then connect to WebRTC if not already connected
                                            if callManager.connectionState == "Disconnected" {
                                                await callManager.connect()
                                            }
                                        } catch {
                                            print("Failed to create endpoint: \(error)")
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(createdEndpointId != nil || callManager.connectionState == "Connected")
                                
                                Button("Delete Endpoint") {
                                    Task {
                                        do {
                                            if let endpointId = createdEndpointId {
                                                try await callManager
                                                    .backendService
                                                    .deleteEndpoint(endpointId: endpointId)
                                                createdEndpointId = nil
                                                print("Deleted Endpoint: \(endpointId)")
                                            } else if let endpointId = callManager.endpoint?.endpointId {
                                                try await callManager
                                                    .backendService
                                                    .deleteEndpoint(endpointId: endpointId)
                                                print("Deleted Endpoint: \(endpointId)")
                                            } else {
                                                print("No endpoint to delete")
                                            }
                                        } catch {
                                            print("Failed to delete endpoint: \(error)")
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(createdEndpointId == nil && callManager.endpoint?.endpointId == nil)
                            }
                            .padding(.horizontal)
                            
                            Text("Endpoint ID: " + (createdEndpointId ?? callManager.endpoint?.endpointId ?? "None"))
                                .font(.caption)
                                .padding(.top, 4)

                            // place calls buttons
                            Spacer(minLength: geometry.size.height * 0.3)

                            Picker("Type", selection: $selectedEndpointType) {
                                ForEach(endpointTypes, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .padding(.horizontal)
                            .onChange(of: selectedEndpointType) { newValue in
                                print(
                                    "selectedEndpointType changed: \(newValue)"
                                )
                            }

                            TextField(
                                "Enter Number or Endpoint",
                                text: $destinationId
                            )
                            .textFieldStyle(RoundedBorderTextFieldStyle())  // Re-enabled for interaction
                            .focused($isInputFocused).font(.title)
                            .padding(.horizontal)
                            .onChange(of: destinationId) { newValue in
                                print("destinationId changed: \(newValue)")
                            }
                            .onSubmit {
                                if !destinationId.isEmpty {
                                    Task {
                                        if selectedEndpointType == .phoneNumber {
                                            // Use dual call flow for phone numbers
                                            if let endpointId = createdEndpointId {
                                                await callManager.placePhoneCall(phoneNumber: destinationId, endpointId: endpointId)
                                            } else {
                                                print("No endpoint created. Please create an endpoint first for phone calls.")
                                            }
                                        } else {
                                            // Use direct connection for endpoints and callIds
                                            await callManager.startCall(
                                                destination: destinationId,
                                                type: selectedEndpointType
                                            )
                                        }
                                    }
                                }
                            }

                            Button(action: {
                                print(
                                    "Call Button Clicked: \(destinationId) (Type: \(selectedEndpointType.rawValue))"
                                )
                                if !destinationId.isEmpty {
                                    Task {
                                        if selectedEndpointType == .phoneNumber {
                                            // Use dual call flow for phone numbers
                                            if let endpointId = createdEndpointId {
                                                await callManager.placePhoneCall(phoneNumber: destinationId, endpointId: endpointId)
                                            } else {
                                                print("No endpoint created. Please create an endpoint first for phone calls.")
                                            }
                                        } else {
                                            // Use direct connection for endpoints and callIds
                                            await callManager.startCall(
                                                destination: destinationId,
                                                type: selectedEndpointType
                                            )
                                        }
                                    }
                                }
                            }) {
                                Text("Connect")
                                    .font(.largeTitle)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.top, 20)
                            .disabled(destinationId.isEmpty || (selectedEndpointType == .phoneNumber && createdEndpointId == nil))

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(callManager.connectionState == "Connected" ? Color.green : (callManager.connectionState.contains("Error") ? Color.red : Color.orange))
                                    .frame(width: 10, height: 10)
                                Text(callManager.connectionState)
                                    .font(.caption)
                                    .foregroundColor(callManager.connectionState == "Connected" ? .green : (callManager.connectionState.contains("Error") ? .red : .gray))
                            }
                            .padding()

                            Spacer()
                        }
                    }

                }
            }
            .navigationTitle("BRTC Dialer")
            .navigationBarTitleDisplayMode(.inline)  // iOS specific
            .toolbar {
                ToolbarItem(placement: .automatic) {  // Changed to .automatic for iOS to match previous
                    Button(action: {
                        showingSettingsSheet = true
                    }) {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView()
            }
            .onChange(of: showingSettingsSheet) { isShowing in
                if !isShowing && settings.areAllSettingsProvided
                    && callManager.connectionState == "Disconnected"
                {
                    Task {
                        await callManager.connect()
                    }
                }
            }
        }
        .animation(.default, value: callManager.isInCall)
    }
}
