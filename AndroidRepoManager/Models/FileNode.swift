import Foundation

/// A file or folder on a device's file system. Folders store only the IDs of their
/// children; the owning `Device` keeps the flat lookup table (mirrors how a real
/// MTP/ADB/volume backend would hand back entries without a full in-memory tree).
struct FileNode: Identifiable, Hashable {
    let id: UUID
    var name: String
    var isFolder: Bool
    /// Byte size for files. Folder sizes are computed by summing children.
    var size: Int64
    var modified: Date
    var childIDs: [UUID]
    var parentID: UUID?

    /// Absolute path on the device, for nodes backed by a real `DeviceFileSystem`
    /// (nil for the in-memory sample data).
    var remotePath: String?
    /// False for a remote folder whose children haven't been listed yet.
    /// Always true for files and for sample data.
    var isLoaded: Bool

    init(
        id: UUID = UUID(),
        name: String,
        isFolder: Bool,
        size: Int64 = 0,
        modified: Date,
        childIDs: [UUID] = [],
        parentID: UUID? = nil,
        remotePath: String? = nil,
        isLoaded: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isFolder = isFolder
        self.size = size
        self.modified = modified
        self.childIDs = childIDs
        self.parentID = parentID
        self.remotePath = remotePath
        self.isLoaded = isLoaded
    }

    var isHidden: Bool { name.hasPrefix(".") }
}
