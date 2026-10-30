import Foundation

struct StorageCategory: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var bytes: Int64
    var colorHex: String
}

struct LargestFolder: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var bytes: Int64
}

struct Device: Identifiable, Hashable {
    var id: String
    var name: String
    var model: String
    var connection: ConnectionKind
    var capacity: Int64
    var lastBackup: String
    var categories: [StorageCategory]
    var largestFolders: [LargestFolder]
    var nodes: [UUID: FileNode]
    var rootID: UUID
    /// Set only for devices backed by a real `DeviceFileSystem` (e.g. ADB); nil for sample data.
    var discovered: DiscoveredDevice? = nil
    /// Bumped by every mutation below. Lets `AppState` cache sorted/filtered listings
    /// instead of re-sorting on every selection change, while still invalidating the
    /// cache the moment the tree actually changes.
    var treeVersion: Int = 0

    var isRemoteBacked: Bool { discovered != nil }

    var usedBytes: Int64 { categories.reduce(0) { $0 + $1.bytes } }
    var freeBytes: Int64 { max(0, capacity - usedBytes) }

    var root: FileNode { nodes[rootID]! }

    func node(_ id: UUID) -> FileNode? { nodes[id] }

    func children(of node: FileNode, showHidden: Bool) -> [FileNode] {
        node.childIDs.compactMap { nodes[$0] }.filter { showHidden || !$0.isHidden }
    }

    func size(of node: FileNode) -> Int64 {
        guard node.isFolder else { return node.size }
        return node.childIDs.compactMap { nodes[$0] }.reduce(0) { $0 + size(of: $1) }
    }

    /// Path of nodes from root to `node`, inclusive. Empty if not found.
    func ancestorPath(to targetID: UUID) -> [FileNode] {
        guard let target = nodes[targetID] else { return [] }
        var chain = [target]
        var current = target
        while let parentID = current.parentID, let parent = nodes[parentID] {
            chain.append(parent)
            current = parent
        }
        return chain.reversed()
    }

    mutating func addNode(_ node: FileNode, toParent parentID: UUID) {
        treeVersion += 1
        var n = node
        n.parentID = parentID
        nodes[n.id] = n
        if var parent = nodes[parentID] {
            parent.childIDs.append(n.id)
            nodes[parentID] = parent
        }
    }

    mutating func removeNodes(ids: Set<UUID>) {
        treeVersion += 1
        var toRemove = ids
        func collectDescendants(_ id: UUID) {
            guard let n = nodes[id], n.isFolder else { return }
            for c in n.childIDs {
                toRemove.insert(c)
                collectDescendants(c)
            }
        }
        for id in ids { collectDescendants(id) }
        for id in toRemove {
            if let n = nodes[id], let parentID = n.parentID, var parent = nodes[parentID] {
                parent.childIDs.removeAll { $0 == id }
                nodes[parentID] = parent
            }
            nodes.removeValue(forKey: id)
        }
    }

    /// Replaces a folder's children with a freshly fetched listing (used by remote
    /// backends once a folder is lazily loaded, or re-loaded).
    mutating func replaceChildren(_ newChildren: [FileNode], of parentID: UUID) {
        guard var parent = nodes[parentID] else { return }
        treeVersion += 1
        removeNodes(ids: Set(parent.childIDs))
        var childIDs: [UUID] = []
        for child in newChildren {
            var c = child
            c.parentID = parentID
            nodes[c.id] = c
            childIDs.append(c.id)
        }
        parent.childIDs = childIDs
        parent.isLoaded = true
        nodes[parentID] = parent
    }

    mutating func renameNode(_ id: UUID, to newName: String) {
        guard var n = nodes[id] else { return }
        treeVersion += 1
        n.name = newName
        nodes[id] = n
    }
}
