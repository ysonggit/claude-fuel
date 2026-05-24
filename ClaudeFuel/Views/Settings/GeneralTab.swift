import SwiftUI

/// General settings for display and startup behavior.
struct GeneralTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Menu bar") {
                Toggle("Show gauge icon only (no text)",
                       isOn: $state.settings.iconOnlyMenuBar)
            }

            Section("Island bar") {
                Toggle("Show island pill at screen notch",
                       isOn: $state.settings.showIsland)
                Text("Displays Claude Code's live 5-hour rate-limit percentage and reset countdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch claude-fuel at login", isOn: launchAtLogin)
            }

            Section("Rate limit polling") {
                Toggle("Enable API rate limit polling", isOn: $state.settings.enableRateLimitPolling)
                Text("Polls the Anthropic API directly for rate-limit data. Covers CLI usage (which doesn't fire the statusLine hook). Requires an API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if state.settings.enableRateLimitPolling {
                    SecureField("Anthropic API key", text: $state.settings.anthropicApiKey)
                        .textContentType(.password)
                    Text("~$0.00001 per poll (Haiku, 1 token). Leave blank to disable API polling even when the toggle is on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { AutoStartService.isEnabled },
            set: { enabled in
                AutoStartService.setEnabled(enabled)
                state.settings.launchAtLogin = AutoStartService.isEnabled
            }
        )
    }
}
