import SwiftUI

/// A filling ring with the percentage inside it.
///
/// Sits in the trailing edge of a row, where an indeterminate spinner used to
/// be. A spinner says "something is happening"; this says how much is left,
/// which is the actual question when a transfer can take minutes.
struct DownloadProgressRing: View {
    let fraction: Double
    var diameter: CGFloat = 32
    var lineWidth: CGFloat = 3

    private var clamped: Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)

            Circle()
                // A trim of exactly zero draws nothing, which reads as a broken
                // control rather than a transfer that has just begun.
                .trim(from: 0, to: max(0.02, clamped))
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int((clamped * 100).rounded()))")
                .font(.system(size: diameter * 0.30, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.3), value: clamped)
        .accessibilityLabel("Downloading")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}
