import Foundation

enum DateFormatting {
    /// Coarse duration for the menu bar / popover: "2h 47m", "8m", "0m".
    /// Seconds are dropped; sub-minute durations show "0m".
    static func durationShort(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Wall-clock time in the user's locale, e.g. "17:34".
    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    /// Relative "X ago" phrasing for the stale-state indicator (FR-U5).
    static func relativeAgo(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }
}
