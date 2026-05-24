import Foundation
import os

/// Polls the Anthropic API periodically to extract rate-limit headers and
/// merges them into `status.json`. This is the fallback data source when
/// the desktop app doesn't trigger the `statusLine` hook (or when the CLI
/// is rate-limited and can't fire it).
///
/// Uses a minimal API call (Haiku, 1 token) to minimise cost. The response
/// headers `anthropic-ratelimit-tokens-*` map to the Codex 5-hour window.
///
/// Thread-safety: all mutable state is accessed on the serial `queue`.
/// Marked `@unchecked Sendable` to satisfy URLSession's `@Sendable` closure.
final class RateLimitPoller: @unchecked Sendable {
    private let queue = DispatchQueue(label: "claude-fuel.rate-limit-poller")
    private var timer: DispatchSourceTimer?
    private let statusURL: URL
    private var apiKey: String = ""

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appending(path: "dev.ysong.claude-fuel",
                                    directoryHint: .isDirectory)
        statusURL = dir.appending(path: "status.json")
    }

    func updateApiKey(_ key: String) {
        queue.async { self.apiKey = key }
    }

    /// Start polling. First poll fires after `initialDelay`, then every
    /// `interval` seconds. Safe to call multiple times.
    func start(interval: TimeInterval = 60, initialDelay: TimeInterval = 5) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + initialDelay,
                       repeating: .seconds(Int(interval)))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Polling

    private func poll() {
        let key = apiKey
        guard !key.isEmpty else { return }

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let lock = OSAllocatedUnfairLock(initialState: [String: String]?.none)
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if error == nil,
               let http = response as? HTTPURLResponse,
               http.statusCode == 200 {
                let h: [String: String] = Dictionary(
                    uniqueKeysWithValues: http.allHeaderFields.compactMap { kv in
                        guard let k = kv.key as? String,
                              let v = kv.value as? String else { return nil }
                        return (k.lowercased(), v)
                    }
                )
                lock.withLock { $0 = h }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 20)

        guard
            let headers = lock.withLock({ $0 }),
            let remainingStr = headers["anthropic-ratelimit-tokens-remaining"],
            let limitStr = headers["anthropic-ratelimit-tokens-limit"],
            let resetStr = headers["anthropic-ratelimit-tokens-reset"],
            let remaining = Int(remainingStr),
            let limit = Int(limitStr),
            limit > 0
        else { return }

        let usedPercentage = Double(limit - remaining) / Double(limit) * 100
        let resetsAt = parseRFC3339(resetStr)

        mergeFiveHour(usedPercentage: usedPercentage, resetsAt: resetsAt)
    }

    // MARK: - Merge

    /// Reads the existing `status.json`, updates only `rate_limits.five_hour`,
    /// and writes back atomically. All other fields (model, cost, context_window,
    /// session_id, etc.) are preserved untouched.
    private func mergeFiveHour(usedPercentage: Double, resetsAt: Int?) {
        var base: [String: Any]
        if let data = try? Data(contentsOf: statusURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            base = json
        } else {
            // No existing file — create a minimal skeleton.
            base = [:]
        }

        var rateLimits = base["rate_limits"] as? [String: Any] ?? [:]
        var fiveHour = rateLimits["five_hour"] as? [String: Any] ?? [:]
        fiveHour["used_percentage"] = usedPercentage
        if let resetsAt {
            fiveHour["resets_at"] = resetsAt
        }
        rateLimits["five_hour"] = fiveHour
        base["rate_limits"] = rateLimits

        guard let data = try? JSONSerialization.data(
            withJSONObject: base, options: .prettyPrinted) else { return }
        try? data.write(to: statusURL, options: .atomic)
    }

    // MARK: - Helpers

    private func parseRFC3339(_ s: String) -> Int? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: s) { return Int(date.timeIntervalSince1970) }
        fmt.formatOptions = [.withInternetDateTime]
        if let date = fmt.date(from: s) { return Int(date.timeIntervalSince1970) }
        return nil
    }
}