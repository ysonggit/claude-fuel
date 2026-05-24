import Foundation

/// Decoded from the JSON blob that Claude Code pipes to the status line
/// script. Contains precise server-side usage data — no local estimation.
struct StatusLineData: Decodable, Equatable {
    let model: Model?
    let contextWindow: ContextWindow?
    let rateLimits: RateLimits?
    let sessionId: String?
    let cost: Cost?

    /// Timestamp when the status.json file was last written (set by watcher, not decoded).
    var fileModifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case model
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
        case sessionId = "session_id"
        case cost
        // fileModifiedAt is set programmatically, not decoded from JSON.
    }

    struct Model: Decodable, Equatable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    struct ContextWindow: Decodable, Equatable {
        let usedPercentage: Double?
        let remainingPercentage: Double?
        let contextWindowSize: Int?
        let totalInputTokens: Int?
        let totalOutputTokens: Int?
        let currentUsage: CurrentUsage?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case remainingPercentage = "remaining_percentage"
            case contextWindowSize = "context_window_size"
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case currentUsage = "current_usage"
        }

        struct CurrentUsage: Decodable, Equatable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }

            var weightedTotal: Int {
                let regular = (inputTokens ?? 0)
                    + (outputTokens ?? 0)
                    + (cacheCreationInputTokens ?? 0)
                let cacheRead = Double(cacheReadInputTokens ?? 0) * 0.1
                return regular + Int(cacheRead.rounded())
            }
        }
    }

    struct RateLimits: Decodable, Equatable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }

        struct Window: Decodable, Equatable {
            let usedPercentage: Double?
            let resetsAt: Int?

            enum CodingKeys: String, CodingKey {
                case usedPercentage = "used_percentage"
                case resetsAt = "resets_at"
            }

            /// Seconds until this window resets, relative to `now`.
            func timeUntilReset(now: Date = Date()) -> TimeInterval? {
                guard let epoch = resetsAt else { return nil }
                return max(0, Date(timeIntervalSince1970: Double(epoch)).timeIntervalSince(now))
            }
        }
    }

    struct Cost: Decodable, Equatable {
        let totalCostUsd: Double?
        let totalDurationMs: Int?

        enum CodingKeys: String, CodingKey {
            case totalCostUsd = "total_cost_usd"
            case totalDurationMs = "total_duration_ms"
        }
    }

    /// Convenience: remaining % for the 5-hour window.
    var fiveHourRemainingPercent: Int? {
        guard let used = rateLimits?.fiveHour?.usedPercentage else { return nil }
        return max(0, Int((100 - used).rounded()))
    }

    /// Convenience: remaining % for the 7-day window.
    var sevenDayRemainingPercent: Int? {
        guard let used = rateLimits?.sevenDay?.usedPercentage else { return nil }
        return max(0, Int((100 - used).rounded()))
    }

    /// Friendly model name ("Opus", "Sonnet", "Haiku").
    var friendlyModelName: String? {
        model?.displayName
    }
}
