import SwiftUI

/// Scrolling bar-chart waveform visualizer for debugging audio transmission.
/// Feed it a rolling buffer of normalized amplitude values (0–1).
struct AudioWaveformView: View {
    let levels: [Float]
    let label: String
    var color: Color = .green

    private let barCount = 50
    private let barSpacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(color.opacity(0.7))

            GeometryReader { geo in
                let totalSpacing = barSpacing * CGFloat(barCount - 1)
                let barWidth = max(1, (geo.size.width - totalSpacing) / CGFloat(barCount))
                let midY = geo.size.height / 2

                Canvas { context, size in
                    let samples = paddedLevels
                    for i in 0..<barCount {
                        let level = CGFloat(samples[i])
                        let halfHeight = max(1, level * midY)
                        let x = CGFloat(i) * (barWidth + barSpacing)
                        let rect = CGRect(
                            x: x,
                            y: midY - halfHeight,
                            width: barWidth,
                            height: halfHeight * 2
                        )
                        let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                        // Fade older bars slightly
                        let ageFraction = Double(i) / Double(barCount)
                        context.fill(path, with: .color(color.opacity(0.25 + 0.75 * ageFraction)))
                    }
                }
            }
            .frame(height: 48)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private var paddedLevels: [Float] {
        if levels.count >= barCount {
            return Array(levels.suffix(barCount))
        }
        return Array(repeating: 0, count: barCount - levels.count) + levels
    }
}

#Preview {
    VStack(spacing: 20) {
        AudioWaveformView(
            levels: (0..<50).map { Float(sin(Double($0) / 5.0) * 0.4 + 0.5) },
            label: "OUTGOING (mic)",
            color: .cyan
        )
        AudioWaveformView(
            levels: [],
            label: "INCOMING (remote) 0.000",
            color: .green
        )
    }
    .padding()
    .background(.black)
}
