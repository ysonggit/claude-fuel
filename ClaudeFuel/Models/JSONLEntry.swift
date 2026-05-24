import Foundation

/// One decoded line of a Claude Code JSONL transcript.
///
/// Decoding is intentionally lenient: unknown top-level fields are ignored
/// (forward-compatible with Claude Code updates) and a line missing `message`
/// or `usage` decodes fine — callers filter those out.
struct JSONLEntry: Decodable {
    let type: String
    let timestamp: Date
    let sessionId: String
    let message: Message?

    struct Message: Decodable {
        let id: String?
        let role: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable, Equatable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationInputTokens: Int
        let cacheReadInputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Missing subfields are treated as zero, never a nil-crash (NFR 4.2).
            inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            cacheCreationInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
            cacheReadInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, timestamp, message
        case sessionId = "sessionId"
    }
}

extension JSONLEntry {
    /// True when this entry is an assistant turn carrying real usage data.
    var isUsageBearing: Bool {
        type == "assistant" && message?.usage != nil
    }
}

extension JSONLEntry.Usage {
    /// Weighted token total per FR-S1: cache reads count at 0.1×, everything
    /// else at full weight.
    var weightedTotal: Double {
        Double(inputTokens + outputTokens + cacheCreationInputTokens)
            + Double(cacheReadInputTokens) * 0.1
    }
}
