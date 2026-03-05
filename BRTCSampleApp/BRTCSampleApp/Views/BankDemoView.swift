import SwiftUI

/// Dedicated tab for the "Acme Bank" branded incoming call demo.
///
/// Demonstrates how a corporation (e.g. a bank) can call customers via WebRTC,
/// showing a branded caller name instead of an anonymous phone number.
/// On a real device, CallKit provides the native iOS incoming call screen.
/// In the simulator, a custom ringing UI is used as a fallback.
struct BankDemoView: View {
    @Bindable var viewModel: CallViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero icon
                    ZStack {
                        Circle()
                            .fill(.blue.gradient)
                            .frame(width: 100, height: 100)
                            .shadow(color: .blue.opacity(0.3), radius: 16, y: 6)

                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 24)

                    // Description
                    VStack(spacing: 12) {
                        Text("Branded Incoming Call")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Simulate a bank calling a customer through the app. The customer sees **\"Acme Bank\"** as the caller — not a random phone number — building trust and increasing answer rates.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // How it works
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How it works")
                            .font(.headline)

                        DemoStepRow(number: 1, text: "Tap **\"Call Me\"** below")
                        DemoStepRow(number: 2, text: "After 3 seconds, the incoming call screen appears")
                        DemoStepRow(number: 3, text: "Tap **Accept** — you'll hear the bank's message")
                        DemoStepRow(number: 4, text: "Tap **End** to hang up when done")
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 20)

                    // Status
                    if !viewModel.statusText.isEmpty {
                        Text(viewModel.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }

                    // Call Me button
                    Button {
                        viewModel.simulateBankCall()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.arrow.down.left.fill")
                                .font(.title3)
                            Text("Call Me")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.blue.gradient, in: Capsule())
                        .shadow(color: .blue.opacity(0.25), radius: 8, y: 4)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                    // Fine print
                    Text("On a real device, this triggers CallKit's native incoming call screen. In the simulator, a custom UI is shown as a fallback.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Branded Calling")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Step Row

private struct DemoStepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.blue, in: Circle())

            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
