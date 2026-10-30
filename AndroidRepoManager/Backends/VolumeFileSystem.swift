import Foundation

/// Backend for SD cards and other removable, mounted volumes. Plain `FileManager` —
/// no subprocess, no sandbox exception needed (unlike ADB's `Process` calls).
struct VolumeFileSystem: DeviceFileSystem {
    private static let resourceKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeIsInternalKey, .volumeLocalizedFormatDescriptionKey,
    ]

    func discoverDevices() async throws -> [DiscoveredDevice] {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.resourceKeys, options: [.skipHiddenVolumes]) ?? []
        var results: [DiscoveredDevice] = []
        for url in volumes {
            guard let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys)) else { continue }
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false
            let isInternal = values.volumeIsInternal ?? true
            guard (isRemovable || isEjectable) && !isInternal else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            let format = values.volumeLocalizedFormatDescription ?? "Removable volume"
            results.append(DiscoveredDevice(id: url.path, serial: url.path, displayName: name, model: "SD card · \(format)", isWireless: false))
        }
        return results
    }

    func connect(address: String, pairingCode: String?) async throws -> DiscoveredDevice {
        throw ShellError.nonZeroExit(1, "SD cards connect automatically when inserted — there's nothing to type here.")
    }

    func list(_ device: DiscoveredDevice, path: String) async throws -> [RemoteEntry] {
        let dirURL = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let contents = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: keys, options: [])
        return contents.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return RemoteEntry(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? Date()
            )
        }
    }

    func storageInfo(_ device: DiscoveredDevice, path: String) async throws -> RemoteStorageInfo {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = Int64(values.volumeAvailableCapacity ?? 0)
        return RemoteStorageInfo(totalBytes: total, usedBytes: max(0, total - available), freeBytes: available)
    }

    func pull(_ device: DiscoveredDevice, remotePath: String, to localURL: URL, progress: TransferProgress) async throws {
        try await Task.detached {
            try Self.copyWithProgress(from: URL(fileURLWithPath: remotePath), to: localURL, progress: progress)
        }.value
    }

    func push(_ device: DiscoveredDevice, localURL: URL, parentPath: String, progress: TransferProgress) async throws -> String {
        let destURL = URL(fileURLWithPath: parentPath).appendingPathComponent(localURL.lastPathComponent)
        try await Task.detached {
            try Self.copyWithProgress(from: localURL, to: destURL, progress: progress)
        }.value
        return destURL.path
    }

    /// A plain `FileManager.copyItem` is one blocking all-or-nothing call with no
    /// way to report progress or stop partway — this does the same copy in chunks
    /// instead, so a large file (camera rolls, backups) actually moves the progress
    /// bar and the cancel button can interrupt it instead of just hiding the row
    /// while the copy keeps running underneath.
    private nonisolated static func copyWithProgress(from sourceURL: URL, to destURL: URL, progress: TransferProgress) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
        guard fm.createFile(atPath: destURL.path, contents: nil) else {
            throw ShellError.nonZeroExit(1, "Couldn't create \(destURL.lastPathComponent).")
        }
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destURL)
        defer { try? output.close() }

        let chunkSize = 4 * 1024 * 1024
        var done: Int64 = 0
        do {
            while true {
                if progress.isCancelled { throw TransferCancelledError() }
                let chunk = input.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                output.write(chunk)
                done += Int64(chunk.count)
                progress.report(done)
            }
        } catch {
            try? output.close()
            try? fm.removeItem(at: destURL)
            throw error
        }
    }

    func delete(_ device: DiscoveredDevice, paths: [String]) async throws {
        try await Task.detached {
            for path in paths {
                try FileManager.default.removeItem(atPath: path)
            }
        }.value
    }

    func makeDirectory(_ device: DiscoveredDevice, parentPath: String, name: String) async throws -> String {
        let path = URL(fileURLWithPath: parentPath).appendingPathComponent(name).path
        try await Task.detached {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }.value
        return path
    }
}
