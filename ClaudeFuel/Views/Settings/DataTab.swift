import SwiftUI

/// Data settings for the Claude Code status-line integration.
struct DataTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section("Claude Code Status Line") {
                LabeledContent("Status file", value: state.statusFilePath)
                LabeledContent("Last update", value: lastUpdateText)
                LabeledContent("Data source", value: "Claude Code rate_limits")
            }

            Section("Why This Source") {
                Text("claude-fuel reads Claude Code's own status-line JSON, including `rate_limits.five_hour.used_percentage` and `resets_at`. Local transcript logs are intentionally ignored because they do not contain the server-side denominator and can stay wrong after resets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Install Script") {
                Text("Use `Scripts/claude-fuel-statusline.sh` as your Claude Code statusLine command. Once Claude Code writes the first payload, the menu bar meter updates from that file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var lastUpdateText: String {
        guard let age = state.statusLineAge else { return "Waiting for status.json" }
        if age < 10 { return "Live" }
        return "\(DateFormatting.durationShort(age)) ago"
    }
}
