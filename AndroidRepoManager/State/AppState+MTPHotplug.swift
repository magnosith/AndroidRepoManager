import Foundation
import IOKit
import IOKit.usb

/// Android phones in "File Transfer" (MTP) mode don't mount like SD cards, so there's
/// no `NSWorkspace` notification to piggyback on. Google's own Android File Transfer
/// solves this with a background helper that watches raw USB hotplug events (confirmed
/// by inspecting its bundled `Android File Transfer Agent.app`, whose `HotPluggable`
/// class does exactly this). This does the same thing with IOKit while our app is
/// running, then asks `libmtp` whether the new USB device is actually an MTP device —
/// cheaper and simpler than trying to pre-filter by vendor/product id ourselves.
extension AppState {
    func startWatchingMTPDevices() {
        guard let notifyPort = IONotificationPortCreate(kIOMainPortDefault) else { return }
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        mtpNotifyPort = notifyPort

        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let addedMatch = IOServiceMatching(kIOUSBDeviceClassName) else { return }
        let addedResult = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, addedMatch, { refcon, iterator in
            AppState.drain(iterator)
            guard let refcon else { return }
            let appState = Unmanaged<AppState>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { appState.handlePossibleMTPChange() }
        }, context, &mtpAddedIterator)
        if addedResult == KERN_SUCCESS {
            AppState.drain(mtpAddedIterator)
        }

        guard let removedMatch = IOServiceMatching(kIOUSBDeviceClassName) else { return }
        let removedResult = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, removedMatch, { refcon, iterator in
            AppState.drain(iterator)
            guard let refcon else { return }
            let appState = Unmanaged<AppState>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { appState.handlePossibleMTPChange() }
        }, context, &mtpRemovedIterator)
        if removedResult == KERN_SUCCESS {
            AppState.drain(mtpRemovedIterator)
        }

        // IOKit's device-level "first match" doesn't reliably refire when a phone
        // switches USB *function* (e.g. ADB-only -> File Transfer) without a full
        // physical detach/reattach — confirmed by testing against a real phone, where
        // switching modes never retriggered the notification above. A light poll is a
        // simple, reliable fallback regardless of how a given phone re-enumerates.
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handlePossibleMTPChange() }
        }
        RunLoop.current.add(timer, forMode: .common)
        mtpPollTimer = timer
    }

    private static func drain(_ iterator: io_iterator_t) {
        guard iterator != 0 else { return }
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    /// Fired on every USB arrival/removal — re-checks which MTP devices libmtp can see
    /// and reconciles our device list (adds new ones, drops ones that went away).
    private func handlePossibleMTPChange() {
        Task {
            guard let found = try? await mtpBackend.discoverDevices() else { return }
            await MainActor.run {
                let foundIDs = Set(found.map(\.id))
                for stale in self.devices.filter({ $0.connection == .usb && !foundIDs.contains($0.discovered?.id ?? "") }) {
                    self.removeDeviceFromState(stale.id, toastText: "\"\(stale.name)\" was disconnected")
                }
                for discovered in found where !self.devices.contains(where: { $0.discovered?.id == discovered.id }) {
                    Task { await self.addMTPDevice(discovered) }
                }
            }
        }
    }

    private func addMTPDevice(_ discovered: DiscoveredDevice) async {
        guard let rootRef = try? await mtpBackend.rootReference(discovered) else { return }
        let rootID = UUID()
        let root = FileNode(id: rootID, name: "Internal storage", isFolder: true, modified: Date(), remotePath: rootRef, isLoaded: false)
        var device = Device(
            id: discovered.id, name: discovered.displayName, model: discovered.model, connection: .usb,
            capacity: 0, lastBackup: "Never", categories: [], largestFolders: [],
            nodes: [rootID: root], rootID: rootID, discovered: discovered
        )
        if let info = try? await mtpBackend.storageInfo(discovered, path: rootRef) {
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
}
