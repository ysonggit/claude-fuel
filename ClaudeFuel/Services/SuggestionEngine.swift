import Foundation

/// Decides whether to nudge the user toward a fresh chat (FR-S4).
/// Pure logic; rate-limiting and notification delivery live elsewhere (FR-N1).
enum SuggestionEngine {

    /// Minimum turns before a session is "old enough" to suggest a reset.
    static let minTurns = 8
    /// Latest turn must cost at least this multiple of the first turn.
    static let costGrowthMultiple = 3.0
    /// Absolute floor so tiny sessions never trigger.
    static let minLatestCost = 3_000.0

    /// True when all FR-S4 conditions hold for the given turn curve.
    static func shouldSuggestFreshChat(turns: [Turn]) -> Bool {
        guard turns.count >= minTurns,
              let first = turns.first,
              let last = turns.last,
              first.marginalCost > 0
        else { return false }

        return last.marginalCost >= first.marginalCost * costGrowthMultiple
            && last.marginalCost >= minLatestCost
    }
}
