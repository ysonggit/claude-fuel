import Foundation

/// Daily usage aggregates (FR-S2). Two figures answer two different
/// questions: "how much in the last day?" vs. "how much since midnight?".
struct DailyState: Equatable {
    /// Weighted tokens in the trailing 24 hours.
    let last24hTokens: Double

    /// Weighted tokens since local midnight today.
    let calendarTodayTokens: Double
}
