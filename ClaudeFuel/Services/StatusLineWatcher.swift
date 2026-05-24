import Foundation

/// Watches `~/Library/Application Support/dev.ysong.claude-fuel/status.json`
/// for updates written by the Claude Code status line script. Emits decoded
/// `StatusLineData` via an `AsyncStream`.
///
/// Uses `DispatchSource.makeFileSystemObjectSource` with a fallback 10s
/// polling timer.
final class StatusLineWatcher: @unchecked Sendable {
    private let fileURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var fallbackTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "claude-fuel.status-line-watcher")
    private var continuation: AsyncStream<StatusLineData?>.Continuation?
    private var lastModified: Date?

    /// Infinite stream of decoded status updates. `nil` means the status file
    /// disappeared and the app should clear any previously displayed reading.
    lazy var updates: AsyncStream<StatusLineData?> = {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }()

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appending(path: "dev.ysong.claude-fuel",
                                    directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        fileURL = dir.appending(path: "status.json")
    }

    var filePath: String {
        fileURL.path
    }

    /// Starts watching. Call once from the app's startup path.
    func start() {
        // Emit the current file state immediately.
        readAndEmit()

        // Try a dispatch source on the file.
        guard let fd = openFile() else {
            startPolling()
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.readAndEmit() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src

        // Fallback polling in case the dispatch source misses events
        // (e.g. the script recreates the file via atomic write).
        startPolling()
    }

    // MARK: - Private

    private func openFile() -> Int32? {
        let fd = open(fileURL.path, O_RDONLY)
        return fd >= 0 ? fd : nil
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in self?.readAndEmit() }
        timer.resume()
        fallbackTimer = timer
    }

    private func readAndEmit() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if lastModified != nil {
                lastModified = nil
                continuation?.yield(nil)
            }
            return
        }

        // Skip if file hasn't changed.
        let modified: Date?
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let mod = attrs[.modificationDate] as? Date {
            if mod == lastModified { return }
            lastModified = mod
            modified = mod
        } else {
            modified = nil
        }

        guard let data = try? Data(contentsOf: fileURL),
              var decoded = try? JSONDecoder().decode(StatusLineData.self, from: data)
        else { return }

        decoded.fileModifiedAt = modified ?? Date()
        continuation?.yield(decoded)
    }
}
