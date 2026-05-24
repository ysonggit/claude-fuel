import SwiftUI

/// Mini bar chart of the active session's marginal-cost curve (FR-U2 §3).
///
/// Each bar is one turn; height is its marginal cost relative to the most
/// expensive turn shown. The curve climbing toward the right is the visual
/// cue behind the fresh-chat suggestion (FR-S3/S4).
struct TurnCurveView: View {
    let turns: [Turn]

    /// Cap on bars drawn — older turns scroll off so each bar stays legible.
    private static let maxBars = 24

    var body: some View {
        let recent = Array(turns.suffix(Self.maxBars))
        let peak = recent.map(\.marginalCost).max() ?? 0

        Canvas { context, size in
            guard recent.count > 1, peak > 0 else { return }
            let gap: CGFloat = 4
            let barWidth = max(
                1,
                (size.width - gap * CGFloat(recent.count - 1)) / CGFloat(recent.count)
            )
            for (index, turn) in recent.enumerated() {
                let fraction = CGFloat(turn.marginalCost / peak)
                let height = max(1, size.height * fraction)
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(x: x, y: size.height - height,
                                  width: barWidth, height: height)
                // Hottest turns shift from soft terracotta to full terracotta.
                let color = fraction > 0.7 ? CFColors.terra : CFColors.terraSoft
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(color)
                )
            }
        }
        .frame(height: 56)
        .accessibilityLabel("Per-turn cost curve, \(recent.count) turns")
    }
}
