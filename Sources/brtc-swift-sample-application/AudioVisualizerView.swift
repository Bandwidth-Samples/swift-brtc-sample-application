import SwiftUI

struct AudioVisualizerView: View {
    @Binding var isEffective: Bool
    @State private var barHeights: [CGFloat] = Array(repeating: 10, count: 20)
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isEffective ? Color.green : Color.gray)
                    .frame(width: 4, height: barHeights[index])
                    .animation(.easeInOut(duration: 0.1), value: barHeights[index])
            }
        }
        .frame(height: 100)
        .padding()
        .background(Color.black.opacity(0.1))
        .cornerRadius(10)
        .onReceive(timer) { _ in
            if isEffective {
                barHeights = barHeights.map { _ in CGFloat.random(in: 10...80) }
            } else {
                barHeights = Array(repeating: 10, count: 20)
            }
        }
    }
}
