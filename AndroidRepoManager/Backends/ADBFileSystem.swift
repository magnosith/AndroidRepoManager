import Foundation

/// Talks to Android devices via the `adb` command line tool the user already has
/// installed (Settings › Connections › ADB location). No bundled binary, no libusb —
/// just `Process` + the same commands you'd type by hand.
struct ADBFileSystem: DeviceFileSystem {
    var adbPathProvider: () -> String

    init(adbPathProvider: @escaping () -> String = { AppSettings.shared.adbPath }) {
        self.adbPathProvider = adbPathProvider
    }

    private func resolvedADBPath() throws -> String {
        guard let path = ShellRunner.resolveExecutable(preferredPath: adbPathProvider(), toolName: "adb") else {
            throw ShellError.executableNotFound(adbPathProvider())
        }
        return path
    }

    private func run(_ arguments: [String], timeout: TimeInterval = 30, progress: TransferProgress? = nil) async throws -> String {
        let adb = try resolvedADBPath()
        return try await ShellRunner.run(executable: adb, arguments: arguments, timeout: timeout, progress: progress)
    }

    // MARK: Discovery

    func discoverDevices() async throws -> [DiscoveredDevice] {
        let output = try await run(["devices", "-l"])
        var results: [DiscoveredDevice] = []
        for line in output.split(separator: "\n").dropFirst() {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 2, tokens[1] == "device" else { continue }
            let serial = tokens[0]
            let modelToken = tokens.first { $0.hasPrefix("model:") }
                .map { String($0.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ") }
            let isWireless = serial.contains(":")
            results.append(DiscoveredDevice(
                id: serial,
                serial: serial,
                displayName: modelToken ?? serial,
                model: modelToken.map { "\($0) · Android" } ?? "Android device",
                isWireless: isWireless
            ))
        }
        return results
    }

    func connect(address: String, pairingCode: String?) async throws -> DiscoveredDevice {
        var connectAddress = address
        if let code = pairingCode, !code.isEmpty {
            let pairOutput = try await run(["pair", address, code])
            if let match = pairOutput.range(of: #"paired to ([^\s]+)"#, options: .regularExpression) {
                connectAddress = String(pairOutput[match]).replacingOccurrences(of: "paired to ", with: "")
            }
        }
        _ = try await run(["connect", connectAddress])
        let devices = try await discoverDevices()
        guard let found = devices.first(where: { $0.serial == connectAddress || $0.serial.hasPrefix(connectAddress) }) else {
            throw ShellError.nonZeroExit(1, "Couldn't find \(connectAddress) after connecting. Check the address and that Wireless debugging is on.")
        }
        return found
    }

    // MARK: Listing

    func list(_ device: DiscoveredDevice, path: String) async throws -> [RemoteEntry] {
        // A trailing slash forces `ls` to list a directory's contents even when the
        // path itself is a symlink (`/sdcard` -> `/storage/self/primary`), instead of
        // showing the link's own line.
        let listPath = path.hasSuffix("/") ? path : path + "/"
        let command = "ls -la \(Self.shellQuote(listPath))"
        let output = try await run(["-s", device.serial, "shell", command])
        let entries = Self.parseLsOutput(output, parentPath: path)
        if entries.isEmpty, output.lowercased().contains("permission denied") {
            throw ShellError.nonZeroExit(1, "Permission denied reading \(path).")
        }
        if entries.isEmpty, output.lowercased().contains("no such file") {
            throw ShellError.nonZeroExit(1, "\(path) no longer exists on the device.")
        }
        return entries
    }

    static func parseLsOutput(_ output: String, parentPath: String) -> [RemoteEntry] {
        let pattern = #"^([-dlbcps])[-rwxsS]{9}[.+@]?\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var results: [RemoteEntry] = []
        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            guard line != "." , !line.hasPrefix("total ") else { continue }
            let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let m = regex.firstMatch(in: line, range: fullRange) else { continue }
            guard let typeRange = Range(m.range(at: 1), in: line),
                  let sizeRange = Range(m.range(at: 2), in: line),
                  let dateRange = Range(m.range(at: 3), in: line),
                  let timeRange = Range(m.range(at: 4), in: line),
                  let nameRange = Range(m.range(at: 5), in: line) else { continue }

            let isDir = line[typeRange] == "d"
            var name = String(line[nameRange])
            if let arrowRange = name.range(of: " -> ") {
                name = String(name[..<arrowRange.lowerBound])
            }
            if name == "." || name == ".." { continue }

            let size = Int64(line[sizeRange]) ?? 0
            let date = formatter.date(from: "\(line[dateRange]) \(line[timeRange])") ?? Date()
            let path = parentPath.hasSuffix("/") ? parentPath + name : parentPath + "/" + name
            results.append(RemoteEntry(name: name, path: path, isDirectory: isDir, size: size, modified: date))
        }
        return results
    }

    // MARK: Storage

    func storageInfo(_ device: DiscoveredDevice, path: String) async throws -> RemoteStorageInfo {
        let output = try await run(["-s", device.serial, "shell", "df -k \(Self.shellQuote(path))"])
        guard let info = Self.parseDf(output) else {
            throw ShellError.nonZeroExit(1, "Couldn't read storage info for \(path).")
        }
        return info
    }

    static func parseDf(_ output: String) -> RemoteStorageInfo? {
        let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        let tokens = lines.dropFirst().joined(separator: " ").split(separator: " ").map(String.init)
        guard tokens.count >= 5 else { return nil }
        let count = tokens.count
        guard let blocks = Int64(tokens[count - 5]),
              let used = Int64(tokens[count - 4]),
              let available = Int64(tokens[count - 3]) else { return nil }
        return RemoteStorageInfo(totalBytes: blocks * 1024, usedBytes: used * 1024, freeBytes: available * 1024)
    }

    // MARK: Transfers

    /// No progress from `adb` itself (its own terminal progress bar isn't a stable,
    /// parseable format across versions) — but cancelling still works, by killing
    /// the process outright (see `ShellRunner`). The timeout is generous since a
    /// deliberate cancel, not a timer, is now what stops a large transfer.
    func pull(_ device: DiscoveredDevice, remotePath: String, to localURL: URL, progress: TransferProgress) async throws {
        do {
            _ = try await run(["-s", device.serial, "pull", remotePath, localURL.path], timeout: 14400, progress: progress)
        } catch is TransferCancelledError {
            try? FileManager.default.removeItem(at: localURL)
            throw TransferCancelledError()
        }
    }

    func push(_ device: DiscoveredDevice, localURL: URL, parentPath: String, progress: TransferProgress) async throws -> String {
        let remotePath = parentPath.hasSuffix("/") ? parentPath + localURL.lastPathComponent : parentPath + "/" + localURL.lastPathComponent
        do {
            _ = try await run(["-s", device.serial, "push", localURL.path, remotePath], timeout: 14400, progress: progress)
        } catch is TransferCancelledError {
            // Best-effort: whatever landed on the device before the kill is incomplete.
            _ = try? await run(["-s", device.serial, "shell", "rm -rf \(Self.shellQuote(remotePath))"])
            throw TransferCancelledError()
        }
        return remotePath
    }

    func delete(_ device: DiscoveredDevice, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let quoted = paths.map(Self.shellQuote).joined(separator: " ")
        _ = try await run(["-s", device.serial, "shell", "rm -rf \(quoted)"])
    }

    func makeDirectory(_ device: DiscoveredDevice, parentPath: String, name: String) async throws -> String {
        let path = parentPath.hasSuffix("/") ? parentPath + name : parentPath + "/" + name
        _ = try await run(["-s", device.serial, "shell", "mkdir -p \(Self.shellQuote(path))"])
        return path
    }

    // MARK: Helpers

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
