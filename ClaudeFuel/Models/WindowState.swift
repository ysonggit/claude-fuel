import Foundation

/// Confidence in the token figures, derived from how many assistant entries
/// carry real (non-placeholder) input counts (FR-S5).
enum Confidence: String, Codable {
    case high, medium, low
}

/// Aggregate of the current 5-hour rate-limit block (FR-S1).
///
/// Claude meters its session limit in *fixed* 5-hour blocks — a block opens at
/// the first activity after a >5h gap and ends exactly 5h later — so this is a
/// fixed-block model, not a rolling window (deviation from the spec's FR-S1
/// rolling phrasing, chosen to track Claude's real reset behaviour).
struct WindowState: Equatable {
    /// Weighted tokens used so far within the current block.
    let tokensUsed: Double

    /// Start of the current 5-hour block. The limit resets `windowLength`
    /// after this moment. `nil` when no block is currently active.
    let windowStartedAt: Date?

    /// Configured window cap; `tokensUsed / cap` is the fill fraction.
    let cap: Double

    let confidence: Confidence

    static let windowLength: TimeInterval = 5 * 60 * 60

    /// Fraction of the cap consumed, clamped to [0, 1].
    var fillFraction: Double {
        guard cap > 0 else { return 0 }
        return min(max(tokensUsed / cap, 0), 1)
    }

    /// Seconds until the current block resets, relative to `now`.
    func timeUntilReset(now: Date = Date()) -> TimeInterval? {
        guard let start = windowStartedAt else { return nil }
        return max(0, start.addingTimeInterval(Self.windowLength).timeIntervalSince(now))
    }
}
