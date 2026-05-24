import SwiftUI

/// Content drawn inside the notch overlay panel. On notch Macs the panel's
/// top portion overlaps the physical notch (black on black, invisible). The
/// visible content is a single row just BELOW the notch, with a flat-top /
/// rounded-bottom shape that makes the notch appear to have grown downward.
struct IslandContentView: View {
    @Environment(AppState.self) private var state

    /// Whether the target screen has a notch.
    let isNotched: Bool

    /// Near-black matching the physical notch.
    private static let ink = Color(hex: 0x0D0D0F)

    var body: some View {
        if isNotched {
            notchedLayout
        } else {
            centredPill
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Notched layout

    private var notchedLayout: some View {
        VStack(spacing: 0) {
            // Invisible spacer covering the notch band (black on black).
            Spacer()

            // Visible content row below the notch.
            contentRow
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // Flat top merges with the notch; rounded bottom corners.
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 0
            )
            .fill(Self.ink)
        )
    }

    // MARK: - Non-notch centred pill

    private var centredPill: some View {
        contentRow
            .padding(.vertical, 7)
            .padding(.horizontal, 16)
            .background(Capsule().fill(Self.ink))
    }

    // MARK: - Shared content

    private var contentRow: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(gaugeColor)
                .frame(width: 7, height: 7)

            Text(remainingText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(percentColor)

            Text(trendArrow)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            if let reset = state.fiveHourResetInterval {
                Text(DateFormatting.durationShort(reset))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Helpers

    private var remainingPercent: Int {
        state.fiveHourRemainingPercent ?? 0
    }

    private var remainingText: String {
        guard let remaining = state.fiveHourRemainingPercent else { return "—" }
        return "\(remaining)%"
    }

    private var gaugeColor: Color {
        if state.isStatusLineStale { return CFColors.amber.opacity(0.6) }
        switch remainingPercent {
        case ..<20: return CFColors.terra
        case ..<50: return CFColors.amber
        default:    return CFColors.ok
        }
    }

    private var percentColor: Color {
        switch remainingPercent {
        case ..<20: return CFColors.terra
        case ..<50: return CFColors.amber
        default:    return .white
        }
    }

    private var trendArrow: String {
        switch state.burnTrend {
        case .accelerating: return "↑"
        case .steady:       return "→"
        case .cooling:      return "↓"
        }
    }
}
