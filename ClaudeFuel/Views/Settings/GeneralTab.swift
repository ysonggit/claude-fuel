import SwiftUI

/// General settings: window cap, daily soft budget, menu-bar style, autostart
/// (FR-U3 General, FR-C1).
struct GeneralTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Rate-limit window") {
                LabeledContent("Window token cap") {
                    TextField("Cap", value: $state.settings.windowTokenCap,
                              format: .number)
                        .labelsHidden()
                        .frame(width: 110)
                        .multilineTextAlignment(.trailing)
                }
                Text("Default 220,000 — conservative for a Pro plan. Calibrate it precisely from the Data tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Daily budget") {
                Toggle("Track a daily soft budget", isOn: budgetEnabled)
                if state.settings.dailySoftBudget != nil {
                    LabeledContent("Tokens per day") {
                        TextField("Budget", value: budgetValue, format: .number)
                            .labelsHidden()
                            .frame(width: 110)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Menu bar") {
                Toggle("Show gauge icon only (no text)",
                       isOn: $state.settings.iconOnlyMenuBar)
            }

            Section("Startup") {
                Toggle("Launch claude-fuel at login", isOn: launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bindings for optional / external state

    private var budgetEnabled: Binding<Bool> {
        Binding(
            get: { state.settings.dailySoftBudget != nil },
            set: { state.settings.dailySoftBudget = $0 ? 200_000 : nil }
        )
    }

    private var budgetValue: Binding<Double> {
        Binding(
            get: { state.settings.dailySoftBudget ?? 0 },
            set: { state.settings.dailySoftBudget = $0 }
        )
    }

    /// Mirrors the real `SMAppService` login-item status (FR-C1).
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
