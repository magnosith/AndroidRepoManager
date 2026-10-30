import Foundation

enum ShellError: Error, LocalizedError {
    case executableNotFound(String)
    case nonZeroExit(Int32, String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Couldn't find \"\(path)\". Check the ADB location in Settings › Connections."
        case .nonZeroExit(_, let message):
            return message.isEmpty ? "The command failed." : message
        case .launchFailed(let message):
            return message
        }
    }
}

/// Minimal async wrapper around `Process`, used by `ADBFileSystem` to shell out to `adb`.
/// Kept off the main actor so a slow/hanging device never blocks the UI.
enum ShellRunner {
    nonisolated static func run(executable: String, arguments: [String], timeout: TimeInterval = 30, progress: TransferProgress? = nil) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ShellError.executableNotFound(executable)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            process.terminationHandler = { finished in
                timeoutWorkItem.cancel()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                if progress?.isCancelled == true {
                    // Terminated by our own `cancel()`, not a real failure — the caller
                    // wants `TransferCancelledError`, not a non-zero-exit error.
                    continuation.resume(throwing: TransferCancelledError())
                } else if finished.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing: ShellError.nonZeroExit(finished.terminationStatus, err.isEmpty ? out : err))
                }
            }

            do {
                try process.run()
                // Attached *after* `run()` so a cancel requested in the race between
                // the two still terminates the process immediately (see `attach`).
                progress?.attach(process)
            } catch {
                timeoutWorkItem.cancel()
                continuation.resume(throwing: ShellError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Resolves an adb-like tool from a user-configured path, falling back to common
    /// install locations and `$PATH` (via `/usr/bin/env`).
    nonisolated static func resolveExecutable(preferredPath: String, toolName: String) -> String? {
        let candidates = [
            preferredPath,
            "/opt/homebrew/bin/\(toolName)",
            "/usr/local/bin/\(toolName)",
            "/usr/bin/\(toolName)",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let fromPath = try? run(executable: "/usr/bin/which", arguments: [toolName]).trimmingCharacters(in: .whitespacesAndNewlines),
           !fromPath.isEmpty {
            return fromPath
        }
        return nil
    }
}

private extension ShellRunner {
    nonisolated static func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
