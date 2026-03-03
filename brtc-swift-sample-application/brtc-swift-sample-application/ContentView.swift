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
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.06, blue: 0.16),
                        Color(red: 0.11, green: 0.07, blue: 0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if callManager.isInCall {
                    ActiveCallView(callManager: callManager)
                        .transition(.move(edge: .bottom))
                } else if callManager.isConnected {
                    dialerView
                } else {
                    endpointSetupView
                }
            }
            .navigationTitle("BRTC Dialer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(
                Color(red: 0.06, green: 0.06, blue: 0.16).opacity(0.95),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingSettingsSheet = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white.opacity(0.75))
                    }
                }

                if callManager.isConnected && !callManager.isInCall {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { deleteEndpoint() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                Text("Delete Endpoint")
                            }
                            .foregroundColor(.red.opacity(0.85))
                            .font(.caption.weight(.medium))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView()
            }
        }
        .animation(.default, value: callManager.isInCall)
        .animation(.default, value: callManager.isConnected)
    }

    // MARK: - Endpoint Setup

    var endpointSetupView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo, Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.indigo.opacity(0.55), radius: 18, y: 6)

                Text("WebRTC Endpoint")
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text("Create an endpoint to connect\nto Bandwidth WebRTC")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Button(action: { createEndpoint() }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    Text("Create Endpoint")
                        .font(.title3.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: 300)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.indigo, Color.purple.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: Color.indigo.opacity(0.5), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            statusIndicator

            Spacer()
        }
        .padding()
    }

    // MARK: - Dialer

    var dialerView: some View {
        GeometryReader { geometry in
            VStack(spacing: 28) {
                Spacer(minLength: geometry.size.height * 0.08)

                // Header icon
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.indigo, Color.purple.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    .shadow(color: Color.indigo.opacity(0.55), radius: 18, y: 6)

                    Text("New Call")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }

                // Endpoint ID display
                if let endpointId = callManager.endpoint?.endpointId {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Endpoint: \(endpointId)")
                            .font(.caption.monospaced())
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }

                // Endpoint type picker
                Picker("Type", selection: $selectedType) {
                    ForEach(endpointTypes, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .colorScheme(.dark)
                .padding(.horizontal, 24)

                // Destination input
                HStack(spacing: 12) {
                    Image(systemName: selectedType == .phoneNumber ? "phone" : "link")
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 18)
                    TextField(
                        selectedType == .phoneNumber ? "Phone Number" : "Endpoint / Call ID",
                        text: $destination
                    )
                    .foregroundColor(.white)
                    .tint(Color.indigo)
                    .font(.title3)
                    .keyboardType(selectedType == .phoneNumber ? .phonePad : .default)
                    .focused($isInputFocused)
                    .onSubmit { placeCall() }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.09))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                // Call button
                Button(action: placeCall) {
                    ZStack {
                        Circle()
                            .fill(
                                canCall
                                    ? LinearGradient(
                                        colors: [Color(red: 0.2, green: 0.85, blue: 0.4), Color.green],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                      )
                                    : LinearGradient(
                                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                      )
                            )
                            .frame(width: 80, height: 80)
                        Image(systemName: "phone.fill")
                            .font(.title)
                            .foregroundColor(canCall ? .white : .white.opacity(0.35))
                    }
                    .shadow(color: canCall ? Color.green.opacity(0.5) : .clear, radius: 18, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(!canCall)
                .animation(.easeInOut(duration: 0.2), value: canCall)

                statusIndicator

                Spacer()
            }
        }
        .onTapGesture { isInputFocused = false }
    }

    var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.7), radius: 5)
            Text(callManager.connectionState)
                .font(.caption.weight(.medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(statusColor.opacity(0.12))
        .cornerRadius(20)
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
        if s == "Connected" || s == "Call Live" { return .green }
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

    func createEndpoint() {
        Task {
            do {
                try await callManager.createAndConnectEndpoint()
            } catch {
                print("Failed to create endpoint: \(error)")
            }
        }
    }

    func deleteEndpoint() {
        Task {
            await callManager.deleteEndpoint()
        }
    }
}
