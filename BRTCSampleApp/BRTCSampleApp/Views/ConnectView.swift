import SwiftUI

struct ConnectView: View {
    @ObservedObject var viewModel: CallViewModel
    @State private var appeared = false
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Spacer().frame(height: 56)

                // App icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, Color(red: 0.0, green: 0.3, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                        .shadow(color: .blue.opacity(0.3), radius: 16, y: 6)

                    Image(systemName: "phone.connection.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(appeared ? 1.0 : 0.5)
                .opacity(urlFieldFocused ? 0 : (appeared ? 1.0 : 0))

                // Title
                VStack(spacing: 6) {
                    Text("Bandwidth RTC")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Real-Time Communications")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
                .opacity(urlFieldFocused ? 0 : (appeared ? 1.0 : 0))
                .frame(height: urlFieldFocused ? 0 : nil)
                .clipped()

                Spacer().frame(height: urlFieldFocused ? 0 : 36)

                // Feature rows (Apple "Welcome to" pattern)
                VStack(spacing: 28) {
                    FeatureRow(
                        icon: "phone.fill",
                        iconColor: .blue,
                        title: "WebRTC Calling",
                        description: "Make and receive calls over the internet with crystal-clear audio quality."
                    )

                    FeatureRow(
                        icon: "clock.fill",
                        iconColor: .orange,
                        title: "Call History",
                        description: "Keep track of your recent calls with direction, duration, and timestamps."
                    )
                }
                .padding(.horizontal, 24)
                .opacity(urlFieldFocused ? 0 : (appeared ? 1.0 : 0))
                .frame(height: urlFieldFocused ? 0 : nil)
                .clipped()

                Spacer().frame(height: urlFieldFocused ? 0 : 36)

                // Server URL label (shown when focused)
                Text("Server URL")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .opacity(urlFieldFocused ? 1 : 0)
                    .frame(height: urlFieldFocused ? nil : 0)
                    .padding(.bottom, urlFieldFocused ? 16 : 0)

                // Server URL card (frosted glass) — single TextField always in hierarchy
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        TextField("Server URL", text: $viewModel.serverURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($urlFieldFocused)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(urlFieldFocused ? .blue.opacity(0.5) : .white.opacity(0.25), lineWidth: urlFieldFocused ? 1 : 0.5)
                )
                .padding(.horizontal, 24)
                .opacity(appeared ? 1.0 : 0)

                Spacer().frame(height: 16)

                // Done button (shown when focused)
                Button("Done") {
                    urlFieldFocused = false
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
                .opacity(urlFieldFocused ? 1 : 0)
                .frame(height: urlFieldFocused ? nil : 0)

                Spacer().frame(height: urlFieldFocused ? 0 : 8)

                // Connect button
                Button {
                    viewModel.connect()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.arrow.up.right.fill")
                        Text("Connect")
                            .fontWeight(.semibold)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(LinearGradient(colors: [.blue, Color(red: 0.0, green: 0.3, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: .blue.opacity(0.25), radius: 8, y: 4)
                }
                .padding(.horizontal, 24)
                .opacity(urlFieldFocused ? 0 : (appeared ? 1.0 : 0))
                .frame(height: urlFieldFocused ? 0 : nil)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.25), value: urlFieldFocused)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.blue.opacity(0.06),
                    Color(.systemGray6),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.12))

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ConnectView(viewModel: CallViewModel())
}
