import Foundation

enum TokenFormatting {
    /// Compact token count: 5432 → "5.4k", 1_200_000 → "1.2M", 850 → "850".
    static func compact(_ tokens: Double) -> String {
        let n = max(0, tokens)
        switch n {
        case 1_000_000...:
            return trimmed(n / 1_000_000) + "M"
        case 1_000...:
            return trimmed(n / 1_000) + "k"
        default:
            return String(Int(n.rounded()))
        }
    }

    /// One decimal place, dropping a trailing ".0" (1.0 → "1", 5.42 → "5.4").
    private static func trimmed(_ value: Double) -> String {
        let r = (value * 10).rounded() / 10
        return r == r.rounded()
            ? String(Int(r))
            : String(format: "%.1f", r)
    }
}
