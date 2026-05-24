import Foundation

/// One conversational turn: a user message plus the assistant response(s)
/// that follow it until the next user message (FR-S3).
struct Turn: Identifiable, Equatable {
    /// Zero-based position within the session.
    let index: Int
    var id: Int { index }

    /// Timestamp of the first assistant entry in this turn.
    let timestamp: Date

    /// New weighted tokens produced *by this turn alone*.
    let newTokens: Double

    /// Marginal cost of this turn: every prior turn's tokens replayed as
    /// context, plus this turn's new tokens. This is what grows super-linearly
    /// and drives the fresh-chat suggestion.
    let marginalCost: Double
}
