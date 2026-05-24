import SwiftUI

/// Data settings: discovered transcripts, the confidence indicator, and
/// percentage-anchored calibration (FR-U3 Data, FR-S5, FR-C2).
struct DataTab: View {
    @Environment(AppState.self) private var state
    @State private var percentInput = ""

    var body: some View {
        Form {
            Section("Transcripts") {
                LabeledContent("Location",
                               value: state.projectsPath ?? "Not found")
                LabeledContent("Files detected",
                               value: "\(state.transcriptCount)")
                LabeledContent("Last activity", value: lastActivityText)
            }

            Section("Confidence") {
                LabeledContent("Current reading", value: confidenceText)
                Text("HIGH means most assistant entries carry real token counts. LOW means the transcripts are dominated by streaming placeholders, so the figures may undercount actual usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calibration") {
                Text("claude-fuel estimates usage from local transcripts — it can't read Claude's exact limit. Anchor it: open Claude → Settings → Usage, read the current “% used”, and enter it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Claude's reported usage", text: $percentInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Text("% used").foregroundStyle(.secondary)
                    Spacer()
                    Button("Calibrate") {
                        if let percent = Double(percentInput) {
                            state.calibrate(observedPercentUsed: percent)
                            percentInput = ""
                        }
                    }
                    .disabled(!calibrateEnabled)
                }
                LabeledContent("Current window cap",
                               value: TokenFormatting.compact(state.window.cap))
                if !state.canCalibrate {
                    Text("Need at least 5,000 tokens of recent usage before calibrating.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Calibration is allowed only with real usage and a valid 0–100 percent.
    private var calibrateEnabled: Bool {
        guard state.canCalibrate, let percent = Double(percentInput) else {
            return false
        }
        return percent > 0 && percent <= 100
    }

    private var confidenceText: String {
        switch state.window.confidence {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    private var lastActivityText: String {
        guard let newest = state.newestModifiedAt else { return "—" }
        return DateFormatting.relativeAgo(newest)
    }
}
