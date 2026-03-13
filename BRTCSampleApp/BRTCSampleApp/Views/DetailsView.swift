import SwiftUI
import BandwidthRTC

struct DetailsView: View {
    @ObservedObject var viewModel: CallViewModel

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Endpoint ID Section
                    sectionView(
                        title: "Endpoint",
                        content: {
                            if let endpointId = viewModel.currentEndpointId, !endpointId.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(endpointId)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(12)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)

                                    Button(action: {
                                        UIPasteboard.general.string = endpointId
                                    }) {
                                        HStack {
                                            Image(systemName: "doc.on.doc")
                                            Text("Copy Endpoint ID")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    }
                                }
                            } else {
                                Text("Not connected")
                                    .foregroundColor(.secondary)
                            }
                        }
                    )

                    // Connection Status Section
                    sectionView(
                        title: "Connection Status",
                        content: {
                            VStack(alignment: .leading, spacing: 12) {
                                statusRow("State", value: connectionStateText)
                                Divider()
                                statusRow("Status", value: viewModel.statusText)
                            }
                        }
                    )

                    // Call Statistics Section
                    if let stats = viewModel.callStats {
                        sectionView(
                            title: "Call Statistics",
                            content: {
                                VStack(alignment: .leading, spacing: 12) {
                                    // Audio Quality
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Audio Quality")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)

                                        statusRow("Codec", value: stats.codec.uppercased())
                                        statusRow("Jitter", value: String(format: "%.1f ms", stats.jitter * 1000))
                                        statusRow("RTT", value: stats.roundTripTime > 0
                                            ? String(format: "%.0f ms", stats.roundTripTime * 1000)
                                            : "n/a")
                                        statusRow("Audio Level", value: String(format: "%.1f%%", stats.audioLevel * 100))
                                    }

                                    Divider().padding(.vertical, 4)

                                    // Packet Statistics
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Packet Statistics")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)

                                        statusRow("Packets Received", value: "\(stats.packetsReceived)")
                                        statusRow("Packets Sent", value: "\(stats.packetsSent)")
                                        statusRow("Packets Lost", value: "\(stats.packetsLost)")
                                        statusRow("Packet Loss", value: String(format: "%.1f%%", packetLossPercent(stats)))
                                    }

                                    Divider().padding(.vertical, 4)

                                    // Bitrate Statistics
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Bitrate")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)

                                        statusRow("Inbound", value: viewModel.formatBitrate(stats.inboundBitrate))
                                        statusRow("Outbound", value: viewModel.formatBitrate(stats.outboundBitrate))
                                    }
                                }
                            }
                        )
                    } else {
                        sectionView(
                            title: "Call Statistics",
                            content: {
                                Text("No statistics available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        )
                    }

                    // Call Duration Section
                    if viewModel.connectionState == .inCall {
                        sectionView(
                            title: "Call Duration",
                            content: {
                                HStack {
                                    Image(systemName: "stopwatch.fill")
                                        .foregroundColor(.blue)
                                    Text(viewModel.callDurationFormatted)
                                        .font(.system(size: 24, weight: .semibold, design: .default))
                                        .monospacedDigit()
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        )
                    }

                    Spacer().frame(height: 8)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Helpers

    private var connectionStateText: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .ringing:
            return "Ringing"
        case .inCall:
            return "In Call"
        }
    }

    private func packetLossPercent(_ stats: CallStatsSnapshot) -> Double {
        let total = stats.packetsReceived + stats.packetsLost
        guard total > 0 else { return 0 }
        return (Double(stats.packetsLost) / Double(total)) * 100.0
    }

    private func sectionView<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            content()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    let vm = CallViewModel()
    vm.connectionState = .inCall
    vm.phoneNumber = "5551234567"
    vm.callDuration = 125

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

    return DetailsView(viewModel: vm)
}
