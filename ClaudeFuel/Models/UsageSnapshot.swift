import Foundation

/// A point-in-time sample of the 5-hour rate-limit gauge, used to compute
/// burn rate and ETA projections. Stored in a capped ring buffer in AppState.
struct UsageSnapshot: Codable {
    let timestamp: Date
    /// Percentage of the 5-hour window already consumed (0–100).
    let usedPercent: Double
    /// The epoch second at which this 5-hour window resets.
    let resetsAt: Int

    /// True when this snapshot belongs to the same rate-limit window as `other`.
    func sameWindow(as other: UsageSnapshot) -> Bool {
        resetsAt == other.resetsAt
    }
}

/// Lightweight ring buffer with a fixed capacity.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func append(_ element: Element) {
        if storage.count >= capacity {
            storage.removeFirst()
        }
        storage.append(element)
    }

    mutating func clear() {
        storage.removeAll()
    }

    var elements: [Element] { storage }
    var last: Element? { storage.last }
    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
}
