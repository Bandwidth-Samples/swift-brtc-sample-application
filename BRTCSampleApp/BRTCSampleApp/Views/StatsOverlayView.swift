import SwiftUI
import BandwidthRTC

/// Live call stats overlay shown on the in-call screen.
/// Tap the pill badge to expand/collapse the detailed stats panel.
struct StatsOverlayView: View {
    let stats: CallStatsSnapshot
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pill badge (always visible)
            statsQualityPill
                .onTapGesture {
                    withAnimation(.spring(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }

            // Expanded detail panel
            if isExpanded {
                detailPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Animate all stat value changes smoothly
        .animation(.easeInOut(duration: 0.6), value: stats.packetsReceived)
        .animation(.easeInOut(duration: 0.6), value: stats.packetsLost)
        .animation(.easeInOut(duration: 0.6), value: stats.packetsSent)
    }

    // MARK: - Quality Pill

    private var qualityColor: Color {
        let lossPercent = packetLossPercent
        let jitterMs = stats.jitter * 1000
        let rttMs = stats.roundTripTime * 1000

        if lossPercent > 5 || jitterMs > 50 || rttMs > 300 { return .red }
        if lossPercent > 1 || jitterMs > 20 || rttMs > 150 { return .yellow }
        return .green
    }

    private var packetLossPercent: Double {
        let total = stats.packetsReceived + stats.packetsLost
        guard total > 0 else { return 0 }
        return (Double(stats.packetsLost) / Double(total)) * 100.0
    }

    private var statsQualityPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(qualityColor)
                .frame(width: 8, height: 8)
                .shadow(color: qualityColor.opacity(0.6), radius: 3)

            Text(stats.codec.uppercased())
                .font(.caption2)
                .fontWeight(.medium)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(isExpanded ? -180 : 0))
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Audio level bar
            HStack {
                Text("Audio Level")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.green.gradient)
                        .frame(
                            width: geo.size.width * min(CGFloat(stats.audioLevel), 1.0),
                            height: 6
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeOut(duration: 0.15), value: stats.audioLevel)
                }
                .frame(width: 80, height: 6)
            }

            Divider().overlay(.white.opacity(0.15))

            statsRow("Jitter", value: String(format: "%.1f ms", stats.jitter * 1000))
            statsRow("Packet Loss", value: String(format: "%.1f%% (%d)", packetLossPercent, stats.packetsLost))
            statsRow("Packets Recv", value: "\(stats.packetsReceived)")
            statsRow("RTT", value: stats.roundTripTime > 0
                ? String(format: "%.0f ms", stats.roundTripTime * 1000)
                : "n/a")
            statsRow("Bitrate In", value: formatBitrate(stats.inboundBitrate))
            statsRow("Bitrate Out", value: formatBitrate(stats.outboundBitrate))
            statsRow("Codec", value: stats.codec)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func statsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText())
        }
    }

    private func formatBitrate(_ bps: Double) -> String {
        if bps > 1_000_000 {
            return String(format: "%.1f Mbps", bps / 1_000_000)
        } else if bps > 1_000 {
            return String(format: "%.0f kbps", bps / 1_000)
        } else if bps > 0 {
            return String(format: "%.0f bps", bps)
        }
        return "---"
    }
}
