import Foundation

/// Watches Claude Code transcripts for changes and emits debounced change
/// events as an `AsyncStream` the app consumes to trigger re-scans (FR-D5).
///
/// Strategy: a dispatch source on the projects root catches structural
/// changes (new sessions/projects); a re-targetable source on the active
/// session file catches the frequent appends. A slow polling timer runs
/// underneath as a correctness safety net for events a source misses or
/// when a source fails to attach.
///
/// All mutable state is confined to `queue`; the public methods only
/// dispatch onto it, which is why `@unchecked Sendable` is sound here.
final class JSONLWatcher: @unchecked Sendable {
    /// Debounced change events. Each element means "something changed — time
    /// to re-scan." Intended to be iterated from the main actor.
    let changes: AsyncStream<Void>

    private let continuation: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "dev.ysong.claude-fuel.watcher")

    private var rootSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedFile: URL?
    private var pollTimer: DispatchSourceTimer?
    private var debounce: DispatchWorkItem?

    /// Coalescing window for bursts of file-system events (FR-D5).
    private let debounceInterval: TimeInterval = 0.5
    /// Safety-net poll cadence; cheap because scans are incremental (FR-D2).
    private let pollInterval: TimeInterval = 15

    init() {
        (changes, continuation) = AsyncStream<Void>.makeStream()
    }

    /// Begins watching `rootDirectory` and starts the polling safety net.
    func start(rootDirectory: URL) {
        queue.async { [self] in
            rootSource = makeSource(for: rootDirectory)
            startPolling()
        }
    }

    /// Re-targets the per-file watcher at the currently active session file.
    /// Passing `nil` (no active session) tears the per-file watcher down.
    func watchActiveFile(_ url: URL?) {
        queue.async { [self] in
            guard watchedFile != url else { return }
            fileSource?.cancel()
            fileSource = nil
            watchedFile = url
            if let url { fileSource = makeSource(for: url) }
        }
    }

    func stop() {
        queue.async { [self] in
            rootSource?.cancel(); rootSource = nil
            fileSource?.cancel(); fileSource = nil
            pollTimer?.cancel(); pollTimer = nil
            debounce?.cancel(); debounce = nil
        }
        continuation.finish()
    }

    // MARK: - Private (all on `queue`)

    private func makeSource(for url: URL) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.fireDebounced() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func fireDebounced() {
        debounce?.cancel()
        let work = DispatchWorkItem { [continuation] in continuation.yield() }
        debounce = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [continuation] in continuation.yield() }
        pollTimer = timer
        timer.resume()
    }
}
