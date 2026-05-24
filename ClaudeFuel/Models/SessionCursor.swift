import Foundation

/// Tracks how far a single JSONL file has already been parsed, so re-scans
/// only read newly appended bytes (FR-D2: O(new bytes)).
struct SessionCursor: Codable, Equatable {
    /// Absolute path of the JSONL file.
    let path: String
    /// Byte offset of the first not-yet-parsed byte.
    var byteOffset: UInt64
    /// File modification time at the moment `byteOffset` was recorded. If the
    /// file's current mtime is older, or its size is smaller than `byteOffset`,
    /// the file was truncated/replaced and must be re-scanned from 0.
    var modifiedAt: Date
}

extension SessionCursor {
    /// Returns true when `attributes` indicate the file was rotated or
    /// truncated since this cursor was recorded — meaning the cursor is stale.
    func isInvalidated(currentSize: UInt64, currentModifiedAt: Date) -> Bool {
        currentSize < byteOffset || currentModifiedAt < modifiedAt
    }
}

/// Codable container persisted to `cursors.json`.
struct CursorStore: Codable {
    var cursors: [String: SessionCursor] = [:]
}
