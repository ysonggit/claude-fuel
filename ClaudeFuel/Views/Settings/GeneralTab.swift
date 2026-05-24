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
