import Foundation

/// A deduplicated, usage-bearing assistant entry — the flattened unit the
/// Estimator consumes.
struct UsageRecord: Equatable {
    /// `message.id` (request ID) when present, else a synthetic unique key.
    let key: String
    let sessionId: String
    let timestamp: Date
    let model: String?
    let usage: JSONLEntry.Usage

    var weightedTotal: Double { usage.weightedTotal }
}

/// Result of one incremental scan across all discovered JSONL files.
struct ScanResult: Equatable {
    let records: [UsageRecord]
    /// Session whose file was modified within the last 30 minutes; if several
    /// qualify, the most recently modified one (FR-D4).
    let activeSessionId: String?
    /// JSONL file backing `activeSessionId`, so the watcher can target it
    /// directly for fast updates (FR-D5).
    let activeFileURL: URL?
    /// Modification time of the newest JSONL file, for the stale indicator.
    let newestModifiedAt: Date?
    /// Number of `.jsonl` transcripts discovered (FR-U3 Data tab).
    let transcriptCount: Int
    /// Absolute path of the projects directory in use, if found.
    let projectsPath: String?
}

/// Discovers Claude Code JSONL transcripts and parses them incrementally.
///
/// An `actor` so concurrent scan requests can't read the same file at once
/// (spec §5.5). State (`records`, `cursors`) accumulates across scans so each
/// re-scan only reads newly appended bytes (FR-D2).
actor JSONLScanner {
    /// Deduplicated records, keyed by `UsageRecord.key`.
    private var records: [String: UsageRecord] = [:]
    /// Per-file parse progress.
    private var cursors: [String: SessionCursor] = [:]
    /// Last-known session ID per file path, so a scan that reads no new bytes
    /// can still report the file's session.
    private var fileSessionIds: [String: String] = [:]

    private let fileManager: FileManager
    private let decoder: JSONDecoder

    /// A JSONL file with mtime within this interval counts as "active".
    private static let activeWindow: TimeInterval = 30 * 60

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONLScanner.makeDecoder()
    }

    // MARK: Discovery (FR-D1)

    /// Returns the projects directory, preferring `~/.claude/projects/` and
    /// falling back to `~/.config/claude/projects/`. `nil` if neither exists.
    func projectsDirectory() -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".claude/projects", directoryHint: .isDirectory),
            home.appending(path: ".config/claude/projects", directoryHint: .isDirectory),
        ]
        return candidates.first { isDirectory($0) }
    }

    /// All `.jsonl` files under the projects directory, excluding `subagents/`
    /// subdirectories (FR-6.6 — subagent breakdown deferred to v0.3).
    func discoverFiles() -> [URL] {
        guard let root = projectsDirectory() else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.pathComponents.contains("subagents") { continue }
            if url.pathExtension == "jsonl" { files.append(url) }
        }
        return files
    }

    // MARK: Incremental scan (FR-D2, FR-D3, FR-D4)

    /// Scans all discovered files for newly appended content and returns the
    /// current deduplicated aggregate.
    func scan() -> ScanResult {
        var newestModified: Date?
        var activeCandidates: [(sessionId: String, url: URL, modifiedAt: Date)] = []

        let files = discoverFiles()
        for url in files {
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = (attrs[.size] as? NSNumber)?.uint64Value,
                  let modifiedAt = attrs[.modificationDate] as? Date
            else { continue }

            if newestModified == nil || modifiedAt > newestModified! {
                newestModified = modifiedAt
            }

            let sessionId = parseFile(url, size: size, modifiedAt: modifiedAt)

            if let sessionId,
               Date().timeIntervalSince(modifiedAt) <= Self.activeWindow {
                activeCandidates.append((sessionId, url, modifiedAt))
            }
        }

        let active = activeCandidates.max { $0.modifiedAt < $1.modifiedAt }

        return ScanResult(
            records: Array(records.values),
            activeSessionId: active?.sessionId,
            activeFileURL: active?.url,
            newestModifiedAt: newestModified,
            transcriptCount: files.count,
            projectsPath: projectsDirectory()?.path
        )
    }

    /// Reads new bytes from one file, merges decoded records, advances the
    /// cursor. Returns the file's `sessionId` if any record was found.
    /// Malformed lines are silently skipped (NFR 4.2).
    private func parseFile(_ url: URL, size: UInt64, modifiedAt: Date) -> String? {
        var cursor = cursors[url.path]
            ?? SessionCursor(path: url.path, byteOffset: 0, modifiedAt: .distantPast)

        // Rotated or truncated → re-scan from the start.
        if cursor.isInvalidated(currentSize: size, currentModifiedAt: modifiedAt) {
            cursor.byteOffset = 0
        }
        guard size > cursor.byteOffset else {
            cursors[url.path] = cursor
            return fileSessionIds[url.path]
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: cursor.byteOffset)
        } catch {
            return nil
        }
        let data = handle.readDataToEndOfFile()

        // Only consume up to the last newline: a trailing partial line means
        // the file is still being written and must wait for the next scan.
        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            return fileSessionIds[url.path]
        }
        let consumable = data[..<data.index(after: lastNewline)]

        var foundSessionId: String?
        for lineData in consumable.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let entry = try? decoder.decode(JSONLEntry.self, from: Data(lineData)),
                  entry.isUsageBearing,
                  let usage = entry.message?.usage
            else { continue }
            foundSessionId = entry.sessionId

            let key = entry.message?.id ?? "\(entry.sessionId):\(entry.timestamp.timeIntervalSince1970)"
            let record = UsageRecord(
                key: key,
                sessionId: entry.sessionId,
                timestamp: entry.timestamp,
                model: entry.message?.model,
                usage: usage
            )
            merge(record)
        }

        cursor.byteOffset += UInt64(consumable.count)
        cursor.modifiedAt = modifiedAt
        cursors[url.path] = cursor
        if let foundSessionId { fileSessionIds[url.path] = foundSessionId }
        return foundSessionId ?? fileSessionIds[url.path]
    }

    /// FR-D3: collapse entries sharing a request ID, keeping the one with the
    /// largest `output_tokens` (streaming entries grow over time).
    private func merge(_ record: UsageRecord) {
        if let existing = records[record.key],
           existing.usage.outputTokens >= record.usage.outputTokens {
            return
        }
        records[record.key] = record
    }

    // MARK: Helpers

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// ISO-8601 decoder that tolerates timestamps with or without fractional
    /// seconds (Claude Code emits the fractional form).
    private static func makeDecoder() -> JSONDecoder {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: d.codingPath, debugDescription: "Bad date: \(raw)")
            )
        }
        return decoder
    }
}
