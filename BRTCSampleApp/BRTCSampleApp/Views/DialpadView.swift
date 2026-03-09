import SwiftUI

struct DialpadView: View {
    let onDigit: (String) -> Void

    private static let keys: [[DialpadKey]] = [
        [.init(digit: "1", letters: ""), .init(digit: "2", letters: "ABC"), .init(digit: "3", letters: "DEF")],
        [.init(digit: "4", letters: "GHI"), .init(digit: "5", letters: "JKL"), .init(digit: "6", letters: "MNO")],
        [.init(digit: "7", letters: "PQRS"), .init(digit: "8", letters: "TUV"), .init(digit: "9", letters: "WXYZ")],
        [.init(digit: "*", letters: ""), .init(digit: "0", letters: "+"), .init(digit: "#", letters: "")],
    ]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Self.keys, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(row) { key in
                        DialpadButton(key: key) {
                            onDigit(key.digit)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Supporting Types

struct DialpadKey: Identifiable, Hashable {
    let digit: String
    let letters: String
    var id: String { digit }
}

struct DialpadButton: View {
    let key: DialpadKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(key.digit)
                    .font(.system(size: 32, weight: .light))

                if !key.letters.isEmpty {
                    Text(key.letters)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                } else {
                    Text(" ")
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(.primary)
            .frame(width: 80, height: 80)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(DialpadButtonStyle())
    }
}

struct DialpadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    DialpadView { _ in }
        .padding()
}
