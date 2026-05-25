import SwiftUI

/// Data settings for the Claude Code status-line integration.
struct DataTab: View {
    @Environment(AppState.self) private var state
    @State private var installError: String?

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
                LabeledContent("Installed at", value: StatusLineScriptInstaller.installedPath.path)
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 7, height: 7)
                        Text(stateLabel)
                    }
                }
                HStack {
                    Button(installButtonTitle, action: install)
                        .disabled(state.statusLineScriptState == .upToDate)
                    Button("Re-check") { state.refreshScriptState() }
                }
                if let installError {
                    Text(installError).font(.caption).foregroundStyle(.red)
                }
                Text("Set `~/.claude/settings.json` → `statusLine.command` to `bash \(StatusLineScriptInstaller.installedPath.path)`. The button above writes the script and makes it executable. \"Out of date\" means the installed copy differs from what this build of claude-fuel expects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshScriptState() }
    }

    private var lastUpdateText: String {
        guard let age = state.statusLineAge else { return "Waiting for status.json" }
        if age < 10 { return "Live" }
        return "\(DateFormatting.durationShort(age)) ago"
    }

    private var stateLabel: String {
        switch state.statusLineScriptState {
        case .notInstalled: return "Not installed"
        case .upToDate:     return "Up to date"
        case .outOfDate:    return "Out of date — reinstall recommended"
        }
    }

    private var stateColor: Color {
        switch state.statusLineScriptState {
        case .notInstalled: return .secondary
        case .upToDate:     return .green
        case .outOfDate:    return .orange
        }
    }

    private var installButtonTitle: String {
        switch state.statusLineScriptState {
        case .notInstalled: return "Install"
        case .upToDate:     return "Installed"
        case .outOfDate:    return "Reinstall"
        }
    }

    private func install() {
        do {
            try state.installStatusLineScript()
            installError = nil
        } catch {
            installError = error.localizedDescription
        }
    }
}
