import SwiftUI

/// Renders the menu bar status item title (FR-U1).
///
/// Format: `<pct-remaining>% · <time-to-reset>`, monospaced digits, with an
/// SF Symbol prefix that escalates as remaining capacity drops, and a `·zz`
/// suffix when the newest session has gone stale.
struct MenuBarTitleView: View {
    let state: AppState

    var body: some View {
        let remaining = remainingPercent
        if state.settings.iconOnlyMenuBar {
            Image(systemName: "gauge.medium")
        } else {
            // MenuBarExtra's label closure renders Text reliably but tends to
            // drop sibling views in an HStack — inline the prefix glyph into
            // the title string instead of composing Image + Text.
            Text(titleText(remaining: remaining))
                .monospacedDigit()
        }
    }

    /// Capacity remaining, 0–100. The popover frames usage as a meter, so the
    /// menu bar shows what's *left*, not what's spent.
    private var remainingPercent: Int {
        Int(((1 - state.window.fillFraction) * 100).rounded())
    }

    private func titleText(remaining: Int) -> String {
        var text = ""
        if let prefix = prefix(forRemaining: remaining) {
            text += prefix + " "
        }
        text += "\(remaining)%"
        if let reset = state.window.timeUntilReset() {
            text += " · " + DateFormatting.durationShort(reset)
        }
        if state.isStale { text += " ·zz" }
        return text
    }

    private func prefix(forRemaining remaining: Int) -> String? {
        switch remaining {
        case ..<20: return "⚠︎"
        case ..<50: return "⏳"
        default: return nil
        }
    }
}
