import SwiftUI
import BandwidthRTC

struct CallView: View {
    @Bindable var viewModel: CallViewModel
    @State private var selectedTab: Tab = .keypad

    enum Tab { case keypad, recents }

    var body: some View {
        ZStack {
            if viewModel.connectionState == .inCall {
                inCallLayout
            } else if viewModel.connectionState == .ringing {
                ringingLayout
            } else {
                TabView(selection: $selectedTab) {
                    dialingLayout
                        .tabItem {
                            Label("Keypad", systemImage: "circle.grid.3x3.fill")
                        }
                        .tag(Tab.keypad)

                    RecentsView(callHistory: viewModel.callHistory) { e164, formatted in
                        // Populate the dialpad with the selected number
                        let digits = e164.filter { $0.isNumber || $0 == "+" }
                        viewModel.phoneNumber = digits
                        selectedTab = .keypad
                    }
                    .tabItem {
                        Label("Recents", systemImage: "clock.fill")
                    }
                    .tag(Tab.recents)
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Ringing Layout (CallKit incoming call UI is active)

    private var ringingLayout: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Caller info
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .padding(.bottom, 16)

                Text("Incoming Call")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.white)

                Text("Incoming Call...")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)

                Spacer()

                // Accept / Decline buttons (iOS-style)
                HStack(spacing: 80) {
                    // Decline
                    Button {
                        viewModel.declineIncomingCall()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .frame(width: 70, height: 70)
                                .background(.red, in: Circle())

                            Text("Decline")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(CallButtonStyle())

                    // Accept
                    Button {
                        viewModel.acceptIncomingCall()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .frame(width: 70, height: 70)
                                .background(.green, in: Circle())

                            Text("Accept")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(CallButtonStyle())
                }
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Dialing Layout (connected, not yet in call)

    private var dialingLayout: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 48)

            if let endpointId = viewModel.currentEndpointId, !endpointId.isEmpty {
                VStack(spacing: 4) {
                    Text("Endpoint ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(endpointId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 12)
            }

            // Phone number display
            Text(viewModel.formattedPhoneNumber)
                .font(.system(size: 36, weight: .light))
                .frame(height: 44)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 32)
                .contentTransition(.numericText())

            Spacer().frame(height: 24)

            // Dialpad
            DialpadView { digit in
                viewModel.dialpadInput(digit)
            }

            Spacer().frame(height: 16)

            // Call + Delete row
            HStack {
                // Spacer to balance delete button
                Color.clear.frame(width: 80, height: 80)

                Spacer()

                // Green CALL button
                Button {
                    viewModel.call()
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(.green.gradient, in: Circle())
                        .shadow(color: .green.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(CallButtonStyle())

                Spacer()

                // Delete/backspace button
                if !viewModel.phoneNumber.isEmpty {
                    Button {
                        viewModel.phoneNumber = String(viewModel.phoneNumber.dropLast())
                    } label: {
                        Image(systemName: "delete.backward.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, height: 80)
                    }
                    .transition(.opacity)
                } else {
                    Color.clear.frame(width: 80, height: 80)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Bottom controls bar
            dialingBottomControls
                .padding(.bottom, 16)
        }
    }

    // MARK: - In Call Layout

    private var inCallLayout: some View {
        ZStack {
            // Full-screen dark background
            Color.black.ignoresSafeArea()

            // Overlay content
            VStack(spacing: 0) {
                // Stats overlay (top of screen)
                if let stats = viewModel.callStats {
                    StatsOverlayView(
                        stats: stats,
                        isExpanded: $viewModel.showStatsOverlay,
                        viewModel: viewModel
                    )
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                }

                Spacer()

                // Contact info + timer
                VStack(spacing: 4) {
                    Text(viewModel.formattedPhoneNumber)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.white)

                    Text(viewModel.callDuration > 0 ? viewModel.callDurationFormatted : viewModel.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.bottom, 24)

                // Audio waveforms (debug: shows transmitted & received audio)
                VStack(spacing: 8) {
                    AudioWaveformView(
                        levels: viewModel.localAudioLevels,
                        label: "OUTGOING (mic)",
                        color: .cyan
                    )
                    let remoteLevel = viewModel.remoteAudioLevels.last ?? 0
                    AudioWaveformView(
                        levels: viewModel.remoteAudioLevels,
                        label: "INCOMING (remote) \(String(format: "%.3f", remoteLevel))",
                        color: .green
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Dialpad overlay (if toggled during a call)
                if viewModel.showDialpad {
                    DialpadView { tone in
                        viewModel.sendDtmf(tone)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Bottom controls on dark gradient
                inCallBottomControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .padding(.top, 12)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7), .black.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)
                    )
            }
        }
    }

    // MARK: - Bottom Controls (Dialing Mode)

    private var dialingBottomControls: some View {
        HStack(spacing: 0) {
            Spacer()

            // Mic
            CallControlButton(
                icon: "mic.slash.fill",
                label: "Mute",
                isActive: !viewModel.isMicEnabled,
                tint: Color.primary
            ) {
                viewModel.toggleMic()
            }

            Spacer()

            // Disconnect
            Button {
                viewModel.disconnect()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 70)
                        .background(Color(.systemGray), in: Circle())

                    Text("Disconnect")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(CallButtonStyle())

            Spacer()
        }
    }

    // MARK: - Bottom Controls (In Call Mode)

    private var inCallBottomControls: some View {
        HStack(spacing: 0) {
            Spacer()

            // Mic
            CallControlButton(
                icon: "mic.slash.fill",
                label: "Mute",
                isActive: !viewModel.isMicEnabled,
                tint: .white
            ) {
                viewModel.toggleMic()
            }

            Spacer()

            // Keypad
            CallControlButton(
                icon: "circle.grid.3x3.fill",
                label: "Keypad",
                isActive: viewModel.showDialpad,
                tint: .white
            ) {
                withAnimation(.spring(duration: 0.3)) {
                    viewModel.showDialpad.toggle()
                }
            }

            Spacer()

            // Hangup
            Button {
                viewModel.hangup()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 70)
                        .background(.red, in: Circle())

                    Text("End")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .buttonStyle(CallButtonStyle())

            Spacer()
        }
    }
}

// MARK: - Call Control Button

struct CallControlButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let tint: Color
    var activeColor: Color = .red
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? activeColor : tint)
                    .frame(width: 70, height: 70)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().fill(Color(.systemGray4).opacity(0.5)))

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(tint.opacity(0.7))
            }
        }
        .buttonStyle(CallButtonStyle())
    }
}

// MARK: - Button Style

struct CallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Dialing") {
    CallView(viewModel: {
        let vm = CallViewModel()
        vm.connectionState = .connected
        vm.phoneNumber = "5551234567"
        return vm
    }())
}

#Preview("Ringing") {
    CallView(viewModel: {
        let vm = CallViewModel()
        vm.connectionState = .ringing
        return vm
    }())
}

#Preview("In Call") {
    CallView(viewModel: {
        let vm = CallViewModel()
        vm.phoneNumber = "5551234567"
        vm.connectionState = .inCall
        vm.callDuration = 65
        vm.localAudioLevels = (0..<50).map { Float(sin(Double($0) / 5.0) * 0.4 + 0.5) }
        vm.remoteAudioLevels = (0..<50).map { Float(cos(Double($0) / 4.0) * 0.3 + 0.35) }
        var stats = CallStatsSnapshot()
        stats.codec = "opus"
        stats.jitter = 0.008
        stats.packetsReceived = 1_200
        stats.packetsLost = 3
        stats.packetsSent = 1_100
        stats.roundTripTime = 0.045
        stats.audioLevel = 0.65
        stats.inboundBitrate = 32_000
        stats.outboundBitrate = 28_000
        vm.callStats = stats
        return vm
    }())
}