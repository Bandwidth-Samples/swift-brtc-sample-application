import SwiftUI

struct ActiveCallView: View {
    @ObservedObject var callManager: CallManager
    @State private var showingDtmfInput = false

    var formattedCallDuration: String {
        let hours = Int(callManager.callDuration) / 3600
        let minutes = Int(callManager.callDuration) / 60 % 60
        let seconds = Int(callManager.callDuration) % 60
        return String(format: "%02i:%02i:%02i", hours, minutes, seconds)
    }

    var body: some View {
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

            VStack(spacing: 0) {
                Spacer()

                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)
                    Image(systemName: "person.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white.opacity(0.9))
                }
                .shadow(color: Color.indigo.opacity(0.45), radius: 24, y: 8)
                .padding(.bottom, 18)

                // Connection state
                Text(callManager.connectionState)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.bottom, 6)

                // Duration
                Text(formattedCallDuration)
                    .font(.system(size: 46, weight: .thin, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.bottom, 36)

                // Audio visualizer card
                VStack(spacing: 16) {
                    audioRow(
                        label: "Remote",
                        icon: "speaker.wave.2.fill",
                        binding: .constant(!callManager.remoteStreams.isEmpty)
                    )
                    Divider()
                        .background(Color.white.opacity(0.12))
                    audioRow(
                        label: "Local",
                        icon: "mic.fill",
                        binding: $callManager.isMuted.not
                    )
                }
                .padding(20)
                .background(Color.white.opacity(0.07))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.11), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                Spacer()

                // Action buttons
                HStack(spacing: 44) {
                    callActionButton(
                        icon: callManager.isMuted ? "mic.slash.fill" : "mic.fill",
                        label: callManager.isMuted ? "Unmute" : "Mute",
                        tint: callManager.isMuted ? .red : Color.white.opacity(0.12)
                    ) {
                        callManager.toggleMute()
                    }

                    // End call button
                    Button(action: { callManager.endCall() }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red, Color(red: 0.8, green: 0.08, blue: 0.08)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 72, height: 72)
                            Image(systemName: "phone.down.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.red.opacity(0.5), radius: 14, y: 5)
                    }
                    .buttonStyle(.plain)

                    callActionButton(
                        icon: "number.square.fill",
                        label: "DTMF",
                        tint: Color.white.opacity(0.12)
                    ) {
                        showingDtmfInput = true
                    }
                    .sheet(isPresented: $showingDtmfInput) {
                        DtmfInputView(callManager: callManager, isShowingSheet: $showingDtmfInput)
                    }
                }
                .padding(.bottom, 52)
            }
        }
    }

    @ViewBuilder
    func audioRow(label: String, icon: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 20)
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.65))
            Spacer()
            AudioVisualizerView(isEffective: binding)
        }
    }

    @ViewBuilder
    func callActionButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.white)
                }
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
    }
}

struct DtmfInputView: View {
    @ObservedObject var callManager: CallManager
    @Binding var isShowingSheet: Bool
    @State private var dtmfDigit: String = ""

    var body: some View {
        NavigationView {
            VStack {
                Text("Enter DTMF Digit")
                    .font(.headline)
                    .padding()

                TextField("Digit (0-9, *, #)", text: $dtmfDigit)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button("Send") {
                    if dtmfDigit.count == 1 && "0123456789*#".contains(dtmfDigit) {
                        callManager.sendDTMF(key: dtmfDigit)
                        isShowingSheet = false
                    }
                }
                .padding()
                .disabled(!(dtmfDigit.count == 1 && "0123456789*#".contains(dtmfDigit)))
            }
            .navigationTitle("DTMF Input")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingSheet = false
                    }
                }
            }
        }
    }
}

extension Binding where Value == Bool {
    var not: Binding<Value> {
        Binding<Value>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}
