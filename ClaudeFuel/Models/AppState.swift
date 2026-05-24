import Foundation
import Observation

/// Top-level observable state. Claude Code's status-line payload is the only
/// usage source: it contains the server-side rate-limit fields that local
/// JSONL transcripts cannot reconstruct reliably.
@MainActor
@Observable
final class AppState {
    private(set) var statusLine: StatusLineData?
    private(set) var displayNow = Date()

    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            syncIslandVisibility()
        }
    }

    private let store = SettingsStore()
    private let settingsWindow = SettingsWindowController()
    private let islandPanel = IslandPanelController()
    private let statusLineWatcher = StatusLineWatcher()

    init() {
        settings = store.load()
        Task { await start() }
    }

    var hasData: Bool { statusLine != nil }

    var statusFilePath: String {
        statusLineWatcher.filePath
    }

    var isStatusLineStale: Bool {
        guard let mod = statusLine?.fileModifiedAt else { return false }
        return displayNow.timeIntervalSince(mod) > 60 || isFiveHourExpired
    }

    var statusLineAge: TimeInterval? {
        guard let mod = statusLine?.fileModifiedAt else { return nil }
        return displayNow.timeIntervalSince(mod)
    }

    private var fiveHourResetDate: Date? {
        guard let resetsAt = statusLine?.rateLimits?.fiveHour?.resetsAt else { return nil }
        return Date(timeIntervalSince1970: Double(resetsAt))
    }

    private var isFiveHourExpired: Bool {
        guard let reset = fiveHourResetDate else { return false }
        return displayNow >= reset
    }

    var fiveHourRemainingPercent: Int? {
        guard statusLine != nil, !isFiveHourExpired else { return nil }
        return statusLine?.fiveHourRemainingPercent
    }

    var sevenDayRemainingPercent: Int? {
        statusLine?.sevenDayRemainingPercent
    }

    var fiveHourResetInterval: TimeInterval? {
        guard let reset = fiveHourResetDate, displayNow < reset else { return nil }
        return reset.timeIntervalSince(displayNow)
    }

    var currentModel: String? {
        statusLine?.friendlyModelName
    }

    var contextUsedPercent: Int? {
        guard let pct = statusLine?.contextWindow?.usedPercentage else { return nil }
        return Int(pct.rounded())
    }

    var currentUsageTokens: Int? {
        statusLine?.contextWindow?.currentUsage?.weightedTotal
    }

    var totalSessionTokens: Int? {
        guard let context = statusLine?.contextWindow else { return nil }
        return (context.totalInputTokens ?? 0) + (context.totalOutputTokens ?? 0)
    }

    var totalCostText: String? {
        guard let cost = statusLine?.cost?.totalCostUsd else { return nil }
        return cost.formatted(.currency(code: "USD").precision(.fractionLength(2...4)))
    }

    var menuBarTitle: String {
        guard let remaining = fiveHourRemainingPercent else { return "—" }
        var text = "\(remaining)%"
        if let reset = fiveHourResetInterval {
            text += " · " + DateFormatting.durationShort(reset)
        }
        if isStatusLineStale { text += " ·zz" }
        return text
    }

    var menuBarSymbol: String {
        guard let remaining = fiveHourRemainingPercent else {
            return "gauge.with.dots.needle.0percent"
        }
        switch remaining {
        case ..<20: return "gauge.with.dots.needle.0percent"
        case ..<50: return "gauge.with.dots.needle.33percent"
        case ..<80: return "gauge.with.dots.needle.50percent"
        default:    return "gauge.with.dots.needle.67percent"
        }
    }

    func showSettings() {
        settingsWindow.show(appState: self)
    }

    func syncIslandVisibility() {
        if settings.showIsland {
            islandPanel.show(appState: self)
        } else {
            islandPanel.hide()
        }
    }

    private func start() async {
        syncIslandVisibility()
        startDisplayClock()
        statusLineWatcher.start()

        for await data in statusLineWatcher.updates {
            statusLine = data
            displayNow = Date()
        }
    }

    private func startDisplayClock() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await MainActor.run {
                    self?.displayNow = Date()
                }
            }
        }
    }
}
