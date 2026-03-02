import BandwidthWebRTC
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var callManager: CallManager
    @State private var showingSettingsSheet = false
    @State private var destination: String = ""
    @State private var selectedType: EndpointType = .phoneNumber
    @FocusState private var isInputFocused: Bool

    let endpointTypes: [EndpointType] = [.phoneNumber, .endpoint, .callId]

    init(settings: SettingsManager) {
        _callManager = StateObject(wrappedValue: CallManager(settings: settings))
    }

    var body: some View {
        NavigationView {
            ZStack {
                if callManager.isInCall {
                    ActiveCallView(callManager: callManager)
                        .transition(.move(edge: .bottom))
                } else {
                    dialerView
                }
            }
            .navigationTitle("BRTC Dialer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingSettingsSheet = true }) {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView()
            }
        }
        .animation(.default, value: callManager.isInCall)
    }

    // MARK: - Dialer

    var dialerView: some View {
        GeometryReader { geometry in
            VStack(spacing: 24) {
                Spacer(minLength: geometry.size.height * 0.25)

                Picker("Type", selection: $selectedType) {
                    ForEach(endpointTypes, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                TextField(
                    selectedType == .phoneNumber ? "Phone Number" : "Endpoint ID / Call ID",
                    text: $destination
                )
                .textFieldStyle(.roundedBorder)
                .font(.title)
                .keyboardType(selectedType == .phoneNumber ? .phonePad : .default)
                .focused($isInputFocused)
                .padding(.horizontal)
                .onSubmit { placeCall() }

                Button(action: placeCall) {
                    Image(systemName: "phone.fill")
                        .font(.largeTitle)
                        .frame(width: 80, height: 80)
                        .background(canCall ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canCall)

                statusIndicator

                Spacer()
            }
        }
        .onTapGesture { isInputFocused = false }
    }

    var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(callManager.connectionState)
                .font(.caption)
                .foregroundColor(statusColor)
        }
    }

    // MARK: - Helpers

    var canCall: Bool {
        !destination.isEmpty && !isConnecting
    }

    var isConnecting: Bool {
        let s = callManager.connectionState
        return s == "Creating Endpoint..." || s == "Connecting to WebRTC..."
            || s.hasPrefix("Calling") || s.hasPrefix("Placing call")
    }

    var statusColor: Color {
        let s = callManager.connectionState
        if s == "Connected" { return .green }
        if s.hasPrefix("Error") { return .red }
        if s == "Disconnected" { return .gray }
        return .orange
    }

    func placeCall() {
        guard canCall else { return }
        isInputFocused = false
        let dest = destination
        let type = selectedType
        Task {
            if type == .phoneNumber {
                await callManager.callPhoneNumber(dest)
            } else {
                await callManager.call(destination: dest, type: type)
            }
        }
    }
}
