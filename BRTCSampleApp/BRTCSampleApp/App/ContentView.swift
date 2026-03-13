import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CallViewModel()

    var body: some View {
        ZStack {
            switch viewModel.connectionState {
            case .disconnected:
                ConnectView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .connecting:
                ConnectingView(viewModel: viewModel)
                    .transition(.opacity)

            case .connected, .ringing, .inCall:
                CallView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.connectionState)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

// MARK: - Connecting View (pulsing animation during connection)

private struct ConnectingView: View {
    @ObservedObject var viewModel: CallViewModel
    @State private var isPulsing = false
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Match ConnectView background
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.blue.opacity(0.06),
                    Color(.systemGray6),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Pulsing icon with expanding ring
                ZStack {
                    // Expanding ring animation
                    Circle()
                        .stroke(.blue.opacity(ringOpacity), lineWidth: 2)
                        .frame(width: 80, height: 80)
                        .scaleEffect(ringScale)

                    // App icon (matches ConnectView)
                    Circle()
                        .fill(LinearGradient(colors: [.blue, Color(red: 0.0, green: 0.3, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                        .shadow(color: .blue.opacity(0.3), radius: 16, y: 6)

                    Image(systemName: "phone.connection.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(isPulsing ? 1.04 : 0.96)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: isPulsing
                )

                // Title (matches ConnectView)
                VStack(spacing: 6) {
                    Text("Bandwidth RTC")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(viewModel.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                Spacer().frame(height: 48)

                // Progress indicator
                ProgressView()
                    .controlSize(.regular)
                    .tint(.blue)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            isPulsing = true
            withAnimation(
                .easeOut(duration: 2.0)
                .repeatForever(autoreverses: false)
            ) {
                ringScale = 2.0
                ringOpacity = 0
            }
        }
    }
}

#Preview {
    ContentView()
}
