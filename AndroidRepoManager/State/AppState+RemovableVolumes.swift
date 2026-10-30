import Foundation
import AppKit

/// SD cards (and other removable volumes) show up without an explicit "connect"
/// step — macOS mounts them, and we just need to notice. This watches for that
/// and for the user pulling the card back out.
extension AppState {
    func startWatchingRemovableVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        volumeMountObserver = center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleVolumeMounted(note)
        }
        volumeUnmountObserver = center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleVolumeUnmounted(note)
        }
        // didMountNotification only fires for mounts that happen while we're already
        // running — a card inserted before launch needs an explicit scan at startup.
        scanForAlreadyMountedSDCards()
    }

    private func scanForAlreadyMountedSDCards() {
        guard settings.autoMountSD else { return }
        Task {
            guard let found = try? await volumeBackend.discoverDevices() else { return }
            for discovered in found {
                await addSDDevice(discovered)
            }
        }
    }

    private func handleVolumeMounted(_ note: Notification) {
        guard settings.autoMountSD, let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
        Task { await self.tryAddSDDevice(at: url) }
    }

    private func handleVolumeUnmounted(_ note: Notification) {
        guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL,
              let device = devices.first(where: { $0.connection == .sd && $0.discovered?.serial == url.path }) else { return }
        removeDeviceFromState(device.id, toastText: "\"\(device.name)\" was ejected")
    }

    /// Finds a just-mounted volume via the real backend and adds it as a device,
    /// unless it's already tracked (e.g. the user connected it manually first).
    func tryAddSDDevice(at url: URL) async {
        guard !devices.contains(where: { $0.connection == .sd && $0.discovered?.serial == url.path }) else { return }
        guard let found = try? await volumeBackend.discoverDevices(), let discovered = found.first(where: { $0.serial == url.path }) else { return }
        await addSDDevice(discovered)
    }

    func addSDDevice(_ discovered: DiscoveredDevice) async {
        var device = makeVolumeDevice(from: discovered)
        if let info = try? await volumeBackend.storageInfo(discovered, path: discovered.serial) {
            device.capacity = info.totalBytes
            device.categories = [StorageCategory(name: "Used", bytes: info.usedBytes, colorHex: "0A84FF")]
        }
        await MainActor.run {
            guard !self.devices.contains(where: { $0.id == device.id }) else { return }
            let shouldSelect = self.devices.isEmpty || self.screen == .connect
            self.devices.append(device)
            self.showToast("Connected to \(device.name)")
            if shouldSelect { self.selectDevice(device.id) }
        }
    }

    func makeVolumeDevice(from discovered: DiscoveredDevice) -> Device {
        let rootID = UUID()
        let root = FileNode(id: rootID, name: discovered.displayName, isFolder: true, modified: Date(), remotePath: discovered.serial, isLoaded: false)
        return Device(
            id: discovered.id,
            name: discovered.displayName,
            model: discovered.model,
            connection: .sd,
            capacity: 0,
            lastBackup: "Never",
            categories: [],
            largestFolders: [],
            nodes: [rootID: root],
            rootID: rootID,
            discovered: discovered
        )
    }
}
