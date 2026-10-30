import Foundation

/// A device found by a backend, before it becomes a full `Device` in `AppState`.
struct DiscoveredDevice: Identifiable, Hashable {
    var id: String
    var serial: String
    var displayName: String
    var model: String
    var isWireless: Bool
}

/// One entry returned by listing a remote directory.
struct RemoteEntry {
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64
    var modified: Date
}

struct RemoteStorageInfo {
    var totalBytes: Int64
    var usedBytes: Int64
    var freeBytes: Int64
}

/// Shared surface every backend (ADB now; MTP and SD later) implements.
/// `AppState` talks to devices only through this protocol, so swapping or
/// adding a backend never touches the UI layer.
protocol DeviceFileSystem {
    func discoverDevices() async throws -> [DiscoveredDevice]
    func connect(address: String, pairingCode: String?) async throws -> DiscoveredDevice
    func list(_ device: DiscoveredDevice, path: String) async throws -> [RemoteEntry]
    func storageInfo(_ device: DiscoveredDevice, path: String) async throws -> RemoteStorageInfo
    /// `progress` reports bytes moved as the transfer runs and can be cancelled from
    /// the UI at any time; implementations should check it wherever they get a
    /// natural chance to (a progress callback, a chunked copy loop) and throw
    /// `TransferCancelledError` once they notice it.
    func pull(_ device: DiscoveredDevice, remotePath: String, to localURL: URL, progress: TransferProgress) async throws
    /// `parentPath` is the destination *folder*'s reference, not the final file path —
    /// each backend decides how to combine it with `localURL`'s name (path-join for
    /// ADB/SD, a separate parent-id for MTP). Returns the new item's own reference,
    /// so the caller can label it correctly for later pull/delete.
    func push(_ device: DiscoveredDevice, localURL: URL, parentPath: String, progress: TransferProgress) async throws -> String
    func delete(_ device: DiscoveredDevice, paths: [String]) async throws
    /// Returns the new folder's own reference (see `push`).
    func makeDirectory(_ device: DiscoveredDevice, parentPath: String, name: String) async throws -> String
}
