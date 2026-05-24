import Foundation
import Observation

/// Top-level observable state. Two data sources feed the usage gauge:
/// 1. Status-line hook (fast, from Claude Code interactive sessions).
/// 2. RateLimitPoller (API header polling, works when statusLine is silent).
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
            syncRateLimitPoller()
        }
    }

    /// Ring buffer of recent status-line snapshots for burn-rate computation.
    /// ~360 entries ≈ 30 min at 5s refresh.
    private var snapshots = RingBuffer<UsageSnapshot>(capacity: 720)

    private let store = SettingsStore()
    private let settingsWindow = SettingsWindowController()
    private let islandPanel = IslandPanelController()
    private let statusLineWatcher = StatusLineWatcher()
    private let rateLimitPoller = RateLimitPoller()
    private var refreshProcess: Process?

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

    /// 5-hour remaining percentage (0–100).
    /// Always shows last known value (even if expired). The UI uses
    /// `isStatusLineStale` to badge it when the window has reset.
    var fiveHourRemainingPercent: Int? {
        statusLine?.fiveHourRemainingPercent
    }

    var sevenDayRemainingPercent: Int? {
        statusLine?.sevenDayRemainingPercent
    }

    /// Time until the 5-hour window resets. Nil when expired.
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

    // MARK: - Burn rate & projections

    /// Burn rate in percentage-points per hour, computed from the snapshot
    /// buffer. `nil` when fewer than 2 snapshots exist in the current window.
    var burnRatePerHour: Double? {
        let pts = snapshots.elements.filter { snap in
            guard let resetsAt = statusLine?.rateLimits?.fiveHour?.resetsAt else { return false }
            return snap.resetsAt == resetsAt
        }
        guard pts.count >= 2,
              let first = pts.first, let last = pts.last else { return nil }
        let dt = last.timestamp.timeIntervalSince(first.timestamp)
        guard dt >= 30 else { return nil } // need ≥30s of data
        let dp = last.usedPercent - first.usedPercent
        guard dp >= 0 else { return nil }
        return dp / (dt / 3600)
    }

    /// Trend direction for the island bar arrow.
    enum BurnTrend { case accelerating, steady, cooling }

    var burnTrend: BurnTrend {
        let pts = snapshots.elements.filter { snap in
            guard let resetsAt = statusLine?.rateLimits?.fiveHour?.resetsAt else { return false }
            return snap.resetsAt == resetsAt
        }
        guard pts.count >= 6 else { return .steady }
        let mid = pts.count / 2
        let firstHalf = Array(pts[..<mid])
        let secondHalf = Array(pts[mid...])

        func rate(_ slice: [UsageSnapshot]) -> Double? {
            guard let a = slice.first, let b = slice.last else { return nil }
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 10 else { return nil }
            return (b.usedPercent - a.usedPercent) / dt
        }

        guard let r1 = rate(firstHalf), let r2 = rate(secondHalf) else { return .steady }
        if r2 > r1 * 1.3 { return .accelerating }
        if r2 < r1 * 0.7 { return .cooling }
        return .steady
    }

    /// Projected time (in seconds) until usage hits 100%, based on current
    /// burn rate. `nil` when burn rate is zero or unknown.
    var etaToLimit: TimeInterval? {
        guard let rate = burnRatePerHour, rate > 0,
              let remaining = fiveHourRemainingPercent else { return nil }
        return Double(remaining) / rate * 3600
    }

    /// True when the projected ETA is shorter than the time until reset,
    /// meaning the user will likely hit the limit before the window resets.
    var willHitLimit: Bool {
        guard let eta = etaToLimit, let reset = fiveHourResetInterval else { return false }
        return eta < reset
    }

    /// Absolute clock time when the 5-hour window resets.
    var fiveHourResetTime: Date? {
        guard let resetsAt = statusLine?.rateLimits?.fiveHour?.resetsAt,
              !isFiveHourExpired else { return nil }
        return Date(timeIntervalSince1970: Double(resetsAt))
    }

    /// 7-day pacing: ratio of budget consumed vs time elapsed in the window.
    enum PacingState { case underPace, onPace, overPace }

    var sevenDayPacing: PacingState? {
        guard let used = statusLine?.rateLimits?.sevenDay?.usedPercentage,
              let resetsAt = statusLine?.rateLimits?.sevenDay?.resetsAt else { return nil }
        let totalWindow: Double = 7 * 24 * 3600
        let resetDate = Date(timeIntervalSince1970: Double(resetsAt))
        let elapsed = totalWindow - resetDate.timeIntervalSince(displayNow)
        guard elapsed > 0 else { return nil }
        let elapsedFraction = elapsed / totalWindow
        let expectedUsed = elapsedFraction * 100
        let ratio = used / expectedUsed
        if ratio < 0.8 { return .underPace }
        if ratio > 1.2 { return .overPace }
        return .onPace
    }

    var sevenDayDaysLeft: Int? {
        guard let resetsAt = statusLine?.rateLimits?.sevenDay?.resetsAt else { return nil }
        let reset = Date(timeIntervalSince1970: Double(resetsAt))
        let seconds = reset.timeIntervalSince(displayNow)
        guard seconds > 0 else { return nil }
        return Int(ceil(seconds / 86400))
    }

    // MARK: - Menu bar

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

    /// Start or stop the API poller based on settings. Only polls when both
    /// the toggle is enabled AND an API key is provided.
    private func syncRateLimitPoller() {
        guard settings.enableRateLimitPolling else {
            rateLimitPoller.stop()
            return
        }
        let key = settings.anthropicApiKey.trimmingCharacters(in: .whitespaces)
        if key.isEmpty {
            rateLimitPoller.stop()
        } else {
            rateLimitPoller.updateApiKey(key)
            rateLimitPoller.start()
        }
    }

    private func start() async {
        syncIslandVisibility()
        syncRateLimitPoller()
        startDisplayClock()
        startRefreshDaemon()

        // Access `updates` first to initialize the AsyncStream continuation,
        // THEN call start() so the initial readAndEmit() can yield.
        let updates = statusLineWatcher.updates
        statusLineWatcher.start()

        for await data in updates {
            statusLine = data
            displayNow = Date()

            // Record snapshot for burn-rate computation.
            if let data, let used = data.rateLimits?.fiveHour?.usedPercentage,
               let resetsAt = data.rateLimits?.fiveHour?.resetsAt {
                let snap = UsageSnapshot(timestamp: Date(),
                                         usedPercent: used,
                                         resetsAt: resetsAt)
                // New window → clear old snapshots.
                if let prev = snapshots.last, !snap.sameWindow(as: prev) {
                    snapshots.clear()
                }
                snapshots.append(snap)
            }
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

    /// Launches a background refresh daemon every 60s to refresh
    /// account-wide rate limits even when the user works in the desktop app.
    private func startRefreshDaemon() {
        // Guard against double-spawn (e.g. if start() is called twice).
        if let existing = refreshProcess, existing.isRunning { return }

        let scriptPath = Bundle.main.bundlePath
            .replacingOccurrences(of: ".app/Contents/MacOS/ClaudeFuel", with: "")
        // Prefer installed script, fall back to bundled.
        let candidates = [
            NSHomeDirectory() + "/.claude/claude-fuel-refresh.sh",
            scriptPath + "/Scripts/claude-fuel-refresh.sh",
        ]
        guard let script = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script, "60"]
        process.standardOutput = nil
        process.standardError = nil
        // Run in its own process group so we can kill the entire tree.
        process.qualityOfService = .utility
        process.terminationHandler = { _ in }

        do {
            try process.run()
            refreshProcess = process
        } catch {
            // Silent failure — refresh is best-effort.
        }
    }

    /// Stop the refresh daemon and API poller when the app quits.
    func stopRefresh() {
        rateLimitPoller.stop()
        guard let process = refreshProcess, process.isRunning else {
            refreshProcess = nil
            return
        }
        // Kill the process group to catch orphaned claude/script children.
        let pid = process.processIdentifier
        kill(-pid, SIGTERM)
        process.terminate()
        refreshProcess = nil
    }
}
