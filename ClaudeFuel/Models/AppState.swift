import Foundation
import Observation

/// Top-level observable state (spec §5.3). SwiftUI views read it directly;
/// every update flows through SwiftUI's Observation tracking — no Combine.
///
/// `@MainActor` so all UI-observable mutation happens on the main actor; the
/// `JSONLScanner` actor and the `JSONLWatcher` queue handle their own work
/// off-main and hand results back here.
@MainActor
@Observable
final class AppState {
    /// Rolling 5-hour window aggregate (FR-S1).
    private(set) var window: WindowState
    /// 24h and calendar-today aggregates (FR-S2).
    private(set) var daily: DailyState
    /// Marginal-cost curve for the active session (FR-S3).
    private(set) var turns: [Turn] = []
    private(set) var activeSessionId: String?
    /// Modification time of the newest transcript, for the stale check.
    private(set) var newestModifiedAt: Date?
    /// Whether the fresh-chat nudge currently applies (FR-S4).
    private(set) var suggestFreshChat = false

    /// Absolute path of the discovered projects directory (FR-U3 Data tab).
    private(set) var projectsPath: String?
    /// Number of transcript files discovered (FR-U3 Data tab).
    private(set) var transcriptCount = 0
    /// Friendly model name of the active session's latest turn ("Opus" etc.).
    private(set) var activeModel: String?

    /// User settings; assigning persists them and triggers a recompute so a
    /// changed window cap is reflected immediately.
    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            Task { await refresh() }
        }
    }

    private let scanner = JSONLScanner()
    private let store = SettingsStore()
    private let notifications = NotificationService()
    private let settingsWindow = SettingsWindowController()
    private var watcher: JSONLWatcher?

    /// Opens (creating on first use) the settings window.
    func showSettings() {
        settingsWindow.show(appState: self)
    }

    init() {
        let loaded = store.load()
        settings = loaded
        window = WindowState(tokensUsed: 0, windowStartedAt: nil,
                             cap: loaded.windowTokenCap, confidence: .low)
        daily = DailyState(last24hTokens: 0, calendarTodayTokens: 0)
        Task { await start() }
    }

    /// True once at least one transcript has been discovered (FR-U4).
    var hasData: Bool { newestModifiedAt != nil }

    /// Title for the menu bar status item (FR-U1). Computed here rather than
    /// in a SwiftUI view because `MenuBarExtra`'s label closure won't render
    /// composite content reliably — feeding the string-based initializer with
    /// an `@Observable`-tracked computed property is the only path that both
    /// shows text and updates when state changes.
    var menuBarTitle: String {
        let remaining = Int(((1 - window.fillFraction) * 100).rounded())
        var text = "\(remaining)%"
        if let reset = window.timeUntilReset() {
            text += " · " + DateFormatting.durationShort(reset)
        }
        if isStale { text += " ·zz" }
        return text
    }

    /// SF Symbol shown to the left of the title — a needle gauge that maps to
    /// the design's terracotta/amber/ink colour shift by selecting a different
    /// fill level as the window depletes.
    var menuBarSymbol: String {
        let remaining = Int(((1 - window.fillFraction) * 100).rounded())
        switch remaining {
        case ..<20: return "gauge.with.dots.needle.0percent"
        case ..<50: return "gauge.with.dots.needle.33percent"
        case ..<80: return "gauge.with.dots.needle.50percent"
        default:    return "gauge.with.dots.needle.67percent"
        }
    }

    /// True when the newest transcript has been idle past the 30-min threshold
    /// (FR-U5).
    var isStale: Bool {
        guard let newest = newestModifiedAt else { return false }
        return Date().timeIntervalSince(newest) > 30 * 60
    }

    /// Whether calibration is meaningful — there must be real usage to anchor
    /// against (FR-C2).
    var canCalibrate: Bool { window.tokensUsed >= 5_000 }

    /// Anchors the window cap to a percentage the user read off Claude's own
    /// usage screen (FR-C2). The app cannot read Claude's true limit from the
    /// transcripts, so the cap is back-computed: if the current block is
    /// `observedPercentUsed`% full, `cap = tokensUsed / (pct / 100)`. From
    /// then on the app's "% left" tracks Claude's number proportionally.
    /// Assigning `settings` persists it and recomputes the window.
    func calibrate(observedPercentUsed: Double) {
        guard canCalibrate,
              observedPercentUsed > 0, observedPercentUsed <= 100
        else { return }
        settings.windowTokenCap =
            (window.tokensUsed / (observedPercentUsed / 100)).rounded()
    }

    // MARK: - Lifecycle

    /// Runs the first scan, attaches the file watcher, then consumes its
    /// change stream for the lifetime of the app. Never returns by design.
    private func start() async {
        notifications.activate()
        await refresh()
        guard let root = await scanner.projectsDirectory() else { return }
        let watcher = JSONLWatcher()
        watcher.start(rootDirectory: root)
        self.watcher = watcher

        for await _ in watcher.changes {
            await refresh()
        }
    }

    /// Re-scans transcripts and recomputes every derived state (spec §5.3).
    func refresh() async {
        let result = await scanner.scan()
        let now = Date()

        window = Estimator.windowState(records: result.records,
                                       cap: settings.windowTokenCap, now: now)
        daily = Estimator.dailyState(records: result.records, now: now)
        activeSessionId = result.activeSessionId
        newestModifiedAt = result.newestModifiedAt
        projectsPath = result.projectsPath
        transcriptCount = result.transcriptCount

        if let active = result.activeSessionId {
            turns = Estimator.turns(records: result.records, sessionId: active)
            let latestModel = result.records
                .filter { $0.sessionId == active }
                .max { $0.timestamp < $1.timestamp }?
                .model
            activeModel = Self.friendlyModelName(latestModel)
        } else {
            turns = []
            activeModel = nil
        }

        if SuggestionEngine.shouldSuggestFreshChat(turns: turns),
           let active = result.activeSessionId {
            await notifications.notifyFreshChat(sessionId: active)
            suggestFreshChat = !notifications.isDismissed(active)
        } else {
            suggestFreshChat = false
        }

        watcher?.watchActiveFile(result.activeFileURL)
    }

    /// Collapses a raw model id ("claude-opus-4-…") to a short display name.
    private static func friendlyModelName(_ raw: String?) -> String? {
        guard let raw = raw?.lowercased() else { return nil }
        if raw.contains("opus") { return "Opus" }
        if raw.contains("sonnet") { return "Sonnet" }
        if raw.contains("haiku") { return "Haiku" }
        return nil
    }
}
