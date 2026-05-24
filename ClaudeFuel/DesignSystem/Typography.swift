import SwiftUI

/// Type ramp for claude-fuel. The preview specifies Source Serif 4 for
/// display/serif roles and Inter for body; until those fonts are bundled this
/// uses the system serif (New York) and system sans (SF), which read closely.
enum CFType {
    /// Wordmark and serif accents.
    static let wordmark   = Font.system(size: 16, weight: .semibold, design: .serif)
    /// Large state-of-charge number.
    static let display    = Font.system(size: 46, weight: .semibold, design: .serif)
    /// "% left" unit beside the display number.
    static let displayUnit = Font.system(size: 20, weight: .medium, design: .serif)
    /// Serif stat-card value.
    static let statValue  = Font.system(size: 17, weight: .semibold, design: .serif)

    /// Uppercase section eyebrow (apply `.tracking` + `.uppercased()` at use).
    static let eyebrow    = Font.system(size: 10, weight: .semibold)
    /// Stat-card key label.
    static let statKey    = Font.system(size: 10, weight: .semibold)
    static let body       = Font.system(size: 12)
    static let caption    = Font.system(size: 11)
}
