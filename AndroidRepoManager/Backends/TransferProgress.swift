import Foundation

/// Bridges a backend's own progress and cancellation into a queued `Transfer`.
///
/// Backends run off the main actor (a dedicated queue for MTP's blocking libmtp
/// calls, a detached `Task` for chunked file copies, a child `Process` for ADB),
/// so this is the thread-safe handle `AppState` holds for the one real transfer
/// that's currently active: it forwards byte counts up via `onProgress`, and lets
/// the UI's cancel button reach back down into whichever backend is running,
/// however it happens to be doing the work.
/// Everything here is guarded by `lock`, not by actor isolation — this type is
/// deliberately opted out of the project's default main-actor isolation
/// (`nonisolated`/`nonisolated(unsafe)` throughout) because the backends calling
/// into it run on their own threads (a libmtp queue, a detached copy `Task`, a
/// `Process` termination callback) and need to report progress and check for
/// cancellation synchronously, without hopping to the main actor each time.
final class TransferProgress: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var cancelled = false
    nonisolated(unsafe) private var process: Process?
    nonisolated(unsafe) private var lastReportTime: Date = .distantPast
    private let reportInterval: TimeInterval = 0.15

    /// Called off the main actor with the cumulative bytes moved so far.
    nonisolated(unsafe) var onProgress: ((Int64) -> Void)?

    nonisolated var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Throttled: a chunked copy or libmtp's callback can fire thousands of times
    /// for a large file, far more often than the UI needs to redraw.
    nonisolated func report(_ doneBytes: Int64) {
        lock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastReportTime) >= reportInterval else {
            lock.unlock()
            return
        }
        lastReportTime = now
        lock.unlock()
        onProgress?(doneBytes)
    }

    /// ADB has no progress hook to poll from inside — the only way to stop it
    /// mid-transfer is to kill the `adb` process directly.
    nonisolated func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { process.terminate() }
    }

    /// Safe to call from any thread, at any time — including before the backend
    /// has started or attached its process.
    nonisolated func cancel() {
        lock.lock()
        cancelled = true
        let runningProcess = process
        lock.unlock()
        runningProcess?.terminate()
    }
}

/// Thrown by a backend once it notices `TransferProgress.isCancelled` mid-transfer.
struct TransferCancelledError: Error, LocalizedError {
    var errorDescription: String? { "Cancelled." }
}
