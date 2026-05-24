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
                    .fill(isLive ? CFColors.ok : CFColors.ink2)
                    .frame(width: 6, height: 6)
                Text(isLive ? "live" : "idle")
                    .font(CFType.caption)
                    .foregroundStyle(CFColors.ink2)
            }
        }
    }

    // MARK: - State of charge

    private var stateOfCharge: some View {
        let remaining = state.fiveHourRemainingPercent
        let fillFraction = remaining.map { Double(100 - $0) / 100.0 } ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            (Text(remaining.map(String.init) ?? "—").font(CFType.display)
                + Text("% left").font(CFType.displayUnit).foregroundColor(CFColors.ink2))
                .monospacedDigit()

            Text(resetLine)
                .font(CFType.body)
                .foregroundStyle(CFColors.ink2)
                .padding(.top, 3)

            if let eta = state.etaToLimit {
                HStack(spacing: 4) {
                    Text(state.willHitLimit ? "⚠" : "✓")
                        .font(.system(size: 10))
                    Text(etaText(eta))
                        .font(CFType.body)
                        .foregroundStyle(state.willHitLimit ? CFColors.terra : CFColors.ink2)
                }
                .padding(.top, 2)
            }

            if let sevenDay = state.sevenDayRemainingPercent {
                HStack(spacing: 4) {
                    Text(sevenDayLine(remaining: sevenDay))
                        .font(CFType.body)
                        .foregroundStyle(CFColors.ink2)
                }
                .padding(.top, 2)
            }

            meterBar(fraction: fillFraction)
                .padding(.top, 14)

            HStack(spacing: 8) {
                statCard("Context", contextText)
                statCard("Current call", currentUsageText)
                statCard("Model", state.currentModel ?? "—")
            }
            .padding(.top, 12)
        }
    }

    private var resetLine: String {
        guard let reset = state.fiveHourResetInterval else {
            return "5-hour window reset"
        }
        var line = "resets in \(DateFormatting.durationShort(reset))"
        if let time = state.fiveHourResetTime {
            line += " (\(DateFormatting.clock(time)))"
        }
        return line
    }

    private func etaText(_ eta: TimeInterval) -> String {
        if state.willHitLimit {
            return "at this pace, hits limit in \(DateFormatting.durationShort(eta))"
        } else {
            return "on pace — won't hit limit before reset"
        }
    }

    private func sevenDayLine(remaining: Int) -> String {
        var line = "7-day: \(remaining)% left"
        if let days = state.sevenDayDaysLeft {
            line += " · \(days)d left"
        }
        if let pacing = state.sevenDayPacing {
            switch pacing {
            case .underPace: line += " · under pace"
            case .onPace:    line += " · on pace"
            case .overPace:  line += " · over pace"
            }
        }
        return line
    }

    private var contextText: String {
        guard let pct = state.contextUsedPercent else { return "—" }
        return "\(pct)% used"
    }

    private var currentUsageText: String {
        guard let tokens = state.currentUsageTokens else { return "—" }
        return TokenFormatting.compact(Double(tokens))
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Waiting for Claude Code")
                .font(CFType.statValue)
            Text("Configure Claude Code's statusLine command to run `Scripts/claude-fuel-statusline.sh`. The meter appears after Claude Code writes its first status payload.")
                .font(CFType.body)
                .foregroundStyle(CFColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 5) {
                Circle().fill(dataSourceColor).frame(width: 7, height: 7)
                Text(dataSourceText)
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

    private var dataSourceColor: Color {
        guard state.hasData else { return CFColors.amber }
        return state.isStatusLineStale ? CFColors.amber : CFColors.ok
    }

    private var dataSourceText: String {
        guard state.hasData else { return "Status Line waiting" }
        if let age = state.statusLineAge {
            if age < 10 { return "Status Line (live)" }
            return "Status Line (\(DateFormatting.durationShort(age)) ago)"
        }
        return "Status Line"
    }

    // MARK: - Shared bits

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CFType.eyebrow)
            .tracking(1)
            .foregroundStyle(CFColors.ink2)
    }

    private var isLive: Bool {
        state.hasData && !state.isStatusLineStale
    }
}
