import Foundation

/// Pure aggregation of `UsageRecord`s into the app's display states.
/// Stateless — every function takes its inputs and `now` explicitly so the
/// logic is deterministic and unit-testable (spec §5.7, §5.5).
enum Estimator {

    // MARK: Window (FR-S1)

    /// Builds the current 5-hour session block (fixed-block model).
    ///
    /// Claude resets its session limit in fixed 5h blocks: a block opens at
    /// the first activity, and the *next* activity at or after `start + 5h`
    /// opens the following block — whether that gap is idle time or simply
    /// continuous use spilling past the 5h mark. We advance to the start of
    /// the most recent block and — unless it has already elapsed — sum every
    /// record since.
    static func windowState(
        records: [UsageRecord],
        cap: Double,
        now: Date = Date()
    ) -> WindowState {
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else {
            return WindowState(tokensUsed: 0, windowStartedAt: nil,
                               cap: cap, confidence: .low)
        }

        // Walk forward; any record at or past `blockStart + 5h` opens a new
        // block, so `blockStart` ends at the start of the most recent one.
        var blockStart = first.timestamp
        for record in sorted.dropFirst() {
            if record.timestamp.timeIntervalSince(blockStart) >= WindowState.windowLength {
                blockStart = record.timestamp
            }
        }

        // A fully elapsed block means the limit has already reset.
        guard now < blockStart.addingTimeInterval(WindowState.windowLength) else {
            return WindowState(tokensUsed: 0, windowStartedAt: nil,
                               cap: cap, confidence: .low)
        }

        let inBlock = sorted.filter { $0.timestamp >= blockStart }
        let used = inBlock.reduce(0) { $0 + $1.weightedTotal }

        return WindowState(
            tokensUsed: used,
            windowStartedAt: blockStart,
            cap: cap,
            confidence: confidence(records: inBlock)
        )
    }

    // MARK: Daily (FR-S2)

    static func dailyState(
        records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyState {
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let midnight = calendar.startOfDay(for: now)

        let last24h = records
            .filter { $0.timestamp >= dayAgo }
            .reduce(0) { $0 + $1.weightedTotal }
        let today = records
            .filter { $0.timestamp >= midnight }
            .reduce(0) { $0 + $1.weightedTotal }

        return DailyState(last24hTokens: last24h, calendarTodayTokens: today)
    }

    // MARK: Turn curve (FR-S3)

    /// Builds the marginal-cost curve for one session, ordered by time.
    ///
    /// Each deduplicated assistant request is treated as one turn — a v0.2
    /// approximation, since precise user/assistant turn segmentation needs the
    /// non-usage-bearing `user` entries the scanner currently filters out.
    /// - `marginalCost`: the full weighted token cost of that request, which
    ///   naturally grows as conversation context accumulates.
    /// - `newTokens`: output + cache-creation tokens — the genuinely new
    ///   content produced that turn.
    static func turns(records: [UsageRecord], sessionId: String) -> [Turn] {
        let ordered = records
            .filter { $0.sessionId == sessionId }
            .sorted { $0.timestamp < $1.timestamp }

        return ordered.enumerated().map { index, record in
            Turn(
                index: index,
                timestamp: record.timestamp,
                newTokens: Double(record.usage.outputTokens
                    + record.usage.cacheCreationInputTokens),
                marginalCost: record.weightedTotal
            )
        }
    }

    // MARK: Confidence (FR-S5)

    /// HIGH/MEDIUM/LOW based on the share of records carrying a real input
    /// count (`input_tokens > 1`, i.e. not a streaming placeholder).
    static func confidence(records: [UsageRecord]) -> Confidence {
        guard !records.isEmpty else { return .low }
        let real = records.filter { $0.usage.inputTokens > 1 }.count
        let ratio = Double(real) / Double(records.count)
        switch ratio {
        case 0.8...: return .high
        case 0.4..<0.8: return .medium
        default: return .low
        }
    }
}
