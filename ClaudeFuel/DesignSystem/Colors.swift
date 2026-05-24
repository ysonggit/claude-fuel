import SwiftUI

/// The claude-fuel palette (design preview `tokens`). Warm "paper" surfaces
/// with a terracotta accent; surface/ink tokens adapt light↔dark, accents are
/// shared across both schemes.
enum CFColors {
    // Accents — identical in light and dark.
    static let terra     = Color(hex: 0xC4633F)
    static let terraSoft = Color(hex: 0xD98B6F)
    static let amber     = Color(hex: 0xC98A2B)
    static let ok        = Color(hex: 0x6F8F5F)

    // Surfaces and ink — scheme-adaptive.
    static let paper  = Color(light: 0xF4EFE7, dark: 0x211E1B)
    static let paper2 = Color(light: 0xECE5D8, dark: 0x322D28)
    static let card   = Color(light: 0xFBF8F2, dark: 0x2A2622)
    static let ink    = Color(light: 0x2B2722, dark: 0xECE6DA)
    static let ink2   = Color(light: 0x6F675C, dark: 0x9B9183)
    static let line   = Color(light: 0xDDD3C2, dark: 0x3A352F)

    // Fresh-chat nudge card.
    static let nudgeFill   = Color(light: 0xF6E7DF, dark: 0x3A2A22)
    static let nudgeStroke = Color(light: 0xE7C3B1, dark: 0x5A4234)
}

extension Color {
    /// Builds a color from a 24-bit `0xRRGGBB` literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }

    /// Builds a scheme-adaptive color from two `0xRRGGBB` literals.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}
