import SwiftUI

/// Root menu-bar popover content (FR-U2), styled to the design preview:
/// warm paper surface, terracotta accent, serif display type, hairline-ruled
/// sections and bordered stat cards.
struct PopoverView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            section { header }
            divider

            if state.hasData {
                section { stateOfCharge }
                if state.turns.count >= 2 {
                    divider
                    section { sessionCurve }
                }
                if state.suggestFreshChat {
                    divider
                    section { suggestionBanner }
                }
                divider
                section { dailySummary }
            } else {
                divider
                section { emptyState }
            }

            divider
            section { footer }
        }
        .frame(width: CFSpacing.popoverWidth)
        .background(CFColors.paper)
        .foregroundStyle(CFColors.ink)
    }

    // MARK: - Section scaffolding

    private func section<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CFSpacing.sectionH)
            .padding(.vertical, CFSpacing.sectionV)
    }

    private var divider: some View {
        Rectangle().fill(CFColors.line).frame(height: 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            (Text("claude") + Text("·").foregroundColor(CFColors.terra) + Text("fuel"))
                .font(CFType.wordmark)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(state.isStale ? CFColors.ink2 : CFColors.ok)
                    .frame(width: 6, height: 6)
                Text(state.isStale ? "idle" : "live")
                    .font(CFType.caption)
                    .foregroundStyle(CFColors.ink2)
            }
        }
    }

    // MARK: - State of charge

    private var stateOfCharge: some View {
        let window = state.window
        let remaining = Int(((1 - window.fillFraction) * 100).rounded())
        return VStack(alignment: .leading, spacing: 0) {
            (Text("\(remaining)").font(CFType.display)
                + Text("% left").font(CFType.displayUnit).foregroundColor(CFColors.ink2))
                .monospacedDigit()

            Text(resetLine(window))
                .font(CFType.body)
                .foregroundStyle(CFColors.ink2)
                .padding(.top, 3)

            meterBar(fraction: window.fillFraction)
                .padding(.top, 14)

            HStack(spacing: 8) {
                statCard("This session", "\(state.turns.count) turns")
                statCard("Latest turn", latestTurnText)
                statCard("Model", state.activeModel ?? "—")
            }
            .padding(.top, 12)
        }
    }

    private func resetLine(_ window: WindowState) -> String {
        let usage = "\(TokenFormatting.compact(window.tokensUsed)) of "
            + "\(TokenFormatting.compact(window.cap)) used"
        guard let reset = window.timeUntilReset() else { return usage }
        return "window resets in \(DateFormatting.durationShort(reset)) · \(usage)"
    }

    private var latestTurnText: String {
        guard let last = state.turns.last else { return "—" }
        return TokenFormatting.compact(last.marginalCost)
    }

    private func meterBar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CFColors.paper2)
                Capsule()
                    .fill(LinearGradient(
                        colors: [CFColors.terraSoft, CFColors.terra],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 9)
    }

    private func statCard(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased())
                .font(CFType.statKey)
                .tracking(0.5)
                .foregroundStyle(CFColors.ink2)
            Text(value)
                .font(CFType.statValue)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(CFColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9).stroke(CFColors.line, lineWidth: 1)
        )
    }

    // MARK: - Session curve

    private var sessionCurve: some View {
        VStack(alignment: .leading, spacing: 9) {
            eyebrow("Active session — cost per turn")
            TurnCurveView(turns: state.turns)
        }
    }

    // MARK: - Fresh-chat nudge

    private var suggestionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("🔥").font(.system(size: 15))
            nudgeText
                .font(CFType.body)
                .foregroundStyle(CFColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CFColors.nudgeFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(CFColors.nudgeStroke, lineWidth: 1)
        )
    }

    private var nudgeText: Text {
        let multiple: String
        if let first = state.turns.first?.marginalCost,
           let last = state.turns.last?.marginalCost,
           first > 0 {
            multiple = String(format: "%.1f×", last / first)
        } else {
            multiple = "several×"
        }
        return Text("Consider a fresh chat. ").bold()
            + Text("This turn costs \(multiple) your first — "
                + "context replay is now most of the spend.")
    }

    // MARK: - Daily

    private var dailySummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            eyebrow("Daily")
            HStack(spacing: 8) {
                statCard("Today",
                         TokenFormatting.compact(state.daily.calendarTodayTokens))
                statCard("Last 24h",
                         TokenFormatting.compact(state.daily.last24hTokens))
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No Claude Code sessions found")
                .font(CFType.statValue)
            Text("Install Claude Code and run `claude` to start a session. "
                + "Usage will appear here automatically.")
                .font(CFType.body)
                .foregroundStyle(CFColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 5) {
                Circle().fill(confidenceColor).frame(width: 7, height: 7)
                Text("Confidence: \(confidenceText)")
                    .font(CFType.caption)
            }
            Spacer()
            HStack(spacing: 14) {
                Button("Settings") { state.showSettings() }
                    .buttonStyle(.plain)
                    .font(CFType.caption)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(CFType.caption)
            }
        }
        .foregroundStyle(CFColors.ink2)
    }

    private var confidenceColor: Color {
        switch state.window.confidence {
        case .high: return CFColors.ok
        case .medium: return CFColors.amber
        case .low: return CFColors.terra
        }
    }

    private var confidenceText: String {
        switch state.window.confidence {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    // MARK: - Shared bits

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CFType.eyebrow)
            .tracking(1)
            .foregroundStyle(CFColors.ink2)
    }
}
