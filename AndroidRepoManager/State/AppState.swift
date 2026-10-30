import Foundation
import Observation
import AppKit
import IOKit
import IOKit.usb

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

struct PendingDelete: Identifiable {
    let id = UUID()
    var nodes: [FileNode]
    var deviceName: String
}

/// Central state for the whole app: selected device, current folder, selection,
/// browser view options, and the screens (browser / storage / onboarding).
/// Backed entirely by fake in-memory data for now; the ADB/MTP/SD backends will
/// plug in by replacing how `devices` is populated and mutated.
@Observable
final class AppState {
    var devices: [Device]
    var selectedDeviceID: Device.ID?

    var path: [UUID] = []
    var backStack: [[UUID]] = []
    var forwardStack: [[UUID]] = []

    var selection: Set<UUID> = []
    var anchorID: UUID?

    var viewMode: ViewMode
    var sortKey: SortKey = .name
    var sortAscending: Bool = true
    var search: String = ""

    var screen: Screen
    var inspectorShown: Bool = true
    var queuePopoverShown: Bool = false

    var pendingDelete: PendingDelete?
    var showDeleteSheet: Bool = false

    var toast: ToastMessage?
    var toastDismissTask: Task<Void, Never>?

    var dragOver: Bool = false

    // Onboarding / connect
    var connectMethod: ConnectionKind = .usb
    var connecting: Bool = false
    var wifiAddress: String = ""
    var wifiCode: String = ""

    // Storage & Backup
    var backupIncludePhotos = true
    var backupIncludeDocuments = true
    var backupIncludeDownloads = true
    var backupIncludeAudio = false

    // "This Mac" pane for the dual layout / backup destination preview
    var macFiles: [(id: UUID, name: String, size: Int64, isFresh: Bool)]

    let settings = AppSettings.shared
    let transferQueue = TransferQueue()
    let adbBackend: DeviceFileSystem = ADBFileSystem()
    let volumeBackend: DeviceFileSystem = VolumeFileSystem()
    let mtpBackend = MTPFileSystem()

    /// Folders currently being listed by a real backend (drives a spinner in the browser).
    var loadingFolderIDs: Set<UUID> = []
    var isProcessingRealTransfer = false
    /// The progress/cancellation handle for whichever real transfer is currently
    /// active, so the Transfers UI's cancel button can reach down into the backend
    /// actually running it (killing a process, aborting a libmtp call, stopping a
    /// chunked copy) instead of just hiding the row while it keeps going underneath.
    var activeTransferProgress: TransferProgress?

    var volumeMountObserver: NSObjectProtocol?
    var volumeUnmountObserver: NSObjectProtocol?

    var mtpNotifyPort: IONotificationPortRef?
    var mtpAddedIterator: io_iterator_t = 0
    var mtpRemovedIterator: io_iterator_t = 0
    var mtpPollTimer: Timer?

    /// Which real backend talks to a given device — ADB over USB/Wi‑Fi, or the
    /// local volume for an SD card. `nil` for sample/demo devices.
    func backend(for device: Device) -> DeviceFileSystem? {
        guard device.discovered != nil else { return nil }
        switch device.connection {
        case .sd: return volumeBackend
        case .usb: return mtpBackend
        case .adb, .wifi: return adbBackend
        }
    }

    init(devices: [Device] = []) {
        self.devices = devices
        self.macFiles = SampleData.macDownloadsFiles().map { (UUID(), $0.name, $0.size, false) }
        self.viewMode = .list
        if let first = devices.first {
            selectedDeviceID = first.id
            path = [first.rootID]
            screen = .browser
        } else {
            screen = .connect
        }
        transferQueue.onComplete = { [weak self] transfer in
            self?.handleTransferComplete(transfer)
        }
        startWatchingRemovableVolumes()
        startWatchingMTPDevices()
    }

    deinit {
        if let observer = volumeMountObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let observer = volumeUnmountObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if mtpAddedIterator != 0 { IOObjectRelease(mtpAddedIterator) }
        if mtpRemovedIterator != 0 { IOObjectRelease(mtpRemovedIterator) }
        mtpPollTimer?.invalidate()
    }

    // MARK: Derived state

    var currentDeviceIndex: Int? {
        guard let id = selectedDeviceID else { return nil }
        return devices.firstIndex { $0.id == id }
    }

    var currentDevice: Device? {
        guard let idx = currentDeviceIndex else { return nil }
        return devices[idx]
    }

    var currentFolder: FileNode? {
        guard let device = currentDevice else { return nil }
        if let lastID = path.last, let node = device.node(lastID), node.isFolder {
            return node
        }
        return device.root
    }

    var breadcrumbs: [FileNode] {
        guard let device = currentDevice, let folderID = currentFolder?.id else { return [] }
        return device.ancestorPath(to: folderID)
    }

    private struct VisibleChildrenCacheKey: Equatable {
        var deviceID: String
        var folderID: UUID
        var treeVersion: Int
        var search: String
        var sortKey: SortKey
        var sortAscending: Bool
        var showHidden: Bool
    }
    private var visibleChildrenCache: (key: VisibleChildrenCacheKey, value: [FileNode])?

    /// Sorting/filtering a large folder (e.g. a camera roll with thousands of photos)
    /// isn't free, so this is cached and only redone when the folder, search, sort or
    /// the tree itself actually changed — not on every selection change, which would
    /// otherwise re-sort on every click.
    var visibleChildren: [FileNode] {
        guard let device = currentDevice, let folder = currentFolder else { return [] }
        let key = VisibleChildrenCacheKey(
            deviceID: device.id, folderID: folder.id, treeVersion: device.treeVersion,
            search: search, sortKey: sortKey, sortAscending: sortAscending, showHidden: settings.showHiddenFiles
        )
        if let cached = visibleChildrenCache, cached.key == key {
            return cached.value
        }
        let kids = computeVisibleChildren(device: device, folder: folder)
        visibleChildrenCache = (key, kids)
        return kids
    }

    private func computeVisibleChildren(device: Device, folder: FileNode) -> [FileNode] {
        var kids = device.children(of: folder, showHidden: settings.showHiddenFiles)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            kids = kids.filter { $0.name.lowercased().contains(query) }
        }
        kids.sort { a, b in
            if a.isFolder != b.isFolder { return a.isFolder && !b.isFolder }
            let ascending = sortAscending
            switch sortKey {
            case .name:
                let result = a.name.localizedStandardCompare(b.name) == .orderedAscending
                return ascending ? result : !result
            case .date:
                return ascending ? a.modified < b.modified : a.modified > b.modified
            case .size:
                let sa = device.size(of: a), sb = device.size(of: b)
                return ascending ? sa < sb : sa > sb
            case .kind:
                let ka = FileKind.info(forName: a.name, isFolder: a.isFolder).label
                let kb = FileKind.info(forName: b.name, isFolder: b.isFolder).label
                let result = ka.localizedStandardCompare(kb) == .orderedAscending
                return ascending ? result : !result
            }
        }
        return kids
    }

    var selectedNodes: [FileNode] {
        guard let device = currentDevice else { return [] }
        return selection.compactMap { device.node($0) }
    }

    var selectedBytes: Int64 {
        guard let device = currentDevice else { return 0 }
        return selectedNodes.reduce(0) { $0 + device.size(of: $1) }
    }

    /// Known top-level folders shown under "Locations" in the sidebar.
    var sidebarLocations: [FileNode] {
        guard let device = currentDevice else { return [] }
        let order = ["DCIM", "Download", "Downloads", "Documents", "Pictures", "Music", "Movies"]
        let children = device.children(of: device.root, showHidden: false)
        return order.compactMap { name in children.first { $0.name == name } }
    }

    var windowTitle: String {
        switch screen {
        case .browser: return currentFolder?.name ?? currentDevice?.name ?? "Android Repo Manager"
        case .storage: return "Storage & Backup"
        case .connect: return "Connect a Device"
        }
    }

    var windowSubtitle: String {
        switch screen {
        case .browser:
            guard let device = currentDevice else { return "" }
            return device.name
        case .storage:
            return currentDevice?.name ?? ""
        case .connect:
            return ""
        }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    var isLoadingCurrentFolder: Bool {
        guard let id = currentFolder?.id else { return false }
        return loadingFolderIDs.contains(id)
    }

    var activeBackupTransfer: Transfer? {
        guard let device = currentDevice else { return nil }
        return transferQueue.items.first {
            $0.deviceID == device.id && $0.direction == .backup && ($0.status == .active || $0.status == .waiting)
        }
    }

    var backupBusy: Bool { activeBackupTransfer != nil }
    var backupProgress: Double { activeBackupTransfer?.fractionDone ?? 0 }
}
