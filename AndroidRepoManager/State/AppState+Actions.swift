import Foundation
import AppKit

extension AppState {
    // MARK: Device selection / navigation

    func selectDevice(_ id: Device.ID) {
        guard let device = devices.first(where: { $0.id == id }) else { return }
        selectedDeviceID = id
        path = [device.rootID]
        backStack = []
        forwardStack = []
        selection = []
        search = ""
        screen = .browser
    }

    func navigate(to newPath: [UUID]) {
        backStack.append(path)
        forwardStack = []
        path = newPath
        selection = []
        search = ""
        screen = .browser
        queuePopoverShown = false
    }

    func goBack() {
        guard let last = backStack.last else { return }
        forwardStack.insert(path, at: 0)
        path = last
        backStack.removeLast()
        selection = []
        screen = .browser
    }

    func goForward() {
        guard let next = forwardStack.first else { return }
        backStack.append(path)
        path = next
        forwardStack.removeFirst()
        selection = []
        screen = .browser
    }

    func goToParent() {
        guard let device = currentDevice, let folder = currentFolder, let parentID = folder.parentID,
              device.node(parentID) != nil else { return }
        let chain = device.ancestorPath(to: parentID).map(\.id)
        navigate(to: chain)
    }

    func openItem(_ node: FileNode) {
        if node.isFolder {
            navigate(to: path + [node.id])
        } else {
            selection = [node.id]
            anchorID = node.id
            inspectorShown = true
        }
    }

    func openFolder(byID id: UUID) {
        guard let device = currentDevice, let node = device.node(id), node.isFolder else { return }
        let chain = device.ancestorPath(to: id).map(\.id)
        navigate(to: chain)
    }

    func openStorageScreen() {
        screen = .storage
        queuePopoverShown = false
    }

    func openConnectScreen() {
        screen = .connect
        connecting = false
    }

    // MARK: Selection

    func handleClick(on id: UUID, shift: Bool, command: Bool) {
        let visible = visibleChildren.map(\.id)
        if shift, let anchor = anchorID, let a = visible.firstIndex(of: anchor), let b = visible.firstIndex(of: id) {
            let range = visible[min(a, b)...max(a, b)]
            selection = Set(range)
        } else if command {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchorID = id
        } else {
            selection = [id]
            anchorID = id
        }
    }

    func selectAll() {
        selection = Set(visibleChildren.map(\.id))
    }

    func clearSelection() {
        selection = []
    }

    func moveSelection(_ delta: Int) {
        let visible = visibleChildren.map(\.id)
        guard !visible.isEmpty else { return }
        let currentIndex = selection.isEmpty ? nil : visible.firstIndex(of: selection.first ?? visible[0])
        let newIndex = max(0, min(visible.count - 1, (currentIndex ?? -1) + delta))
        let id = visible[newIndex]
        selection = [id]
        anchorID = id
    }

    // MARK: Sorting / view mode

    func setSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }

    func toggleInspector() { inspectorShown.toggle() }

    // MARK: Lazy loading (real backends)

    /// Lists a remote folder the first time it's opened. No-op for sample data,
    /// which is already fully in memory.
    func ensureLoaded(folder: FileNode) {
        guard let device = currentDevice, let discovered = device.discovered, let backend = backend(for: device) else { return }
        guard folder.isFolder, !folder.isLoaded, !loadingFolderIDs.contains(folder.id) else { return }
        guard let remotePath = folder.remotePath else { return }
        loadingFolderIDs.insert(folder.id)
        let deviceID = device.id
        Task {
            do {
                let entries = try await backend.list(discovered, path: remotePath)
                await MainActor.run {
                    self.applyListing(entries, parentID: folder.id, deviceID: deviceID)
                    self.loadingFolderIDs.remove(folder.id)
                }
            } catch {
                await MainActor.run {
                    self.loadingFolderIDs.remove(folder.id)
                    self.showToast("Couldn't list \(remotePath): \(error.localizedDescription)")
                }
            }
        }
    }

    private func applyListing(_ entries: [RemoteEntry], parentID: UUID, deviceID: Device.ID) {
        guard let idx = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        let children = entries.map { entry in
            FileNode(
                name: entry.name, isFolder: entry.isDirectory, size: entry.size, modified: entry.modified,
                remotePath: entry.path, isLoaded: !entry.isDirectory
            )
        }
        devices[idx].replaceChildren(children, of: parentID)
    }

    // MARK: New folder

    func createNewFolder() {
        guard let idx = currentDeviceIndex, let folder = currentFolder else { return }
        let existingNames = Set(devices[idx].children(of: folder, showHidden: true).map(\.name))
        var name = "untitled folder"
        var counter = 2
        while existingNames.contains(name) {
            name = "untitled folder \(counter)"
            counter += 1
        }

        if let discovered = devices[idx].discovered, let parentPath = folder.remotePath, let backend = backend(for: devices[idx]) {
            Task {
                do {
                    let childRef = try await backend.makeDirectory(discovered, parentPath: parentPath, name: name)
                    await MainActor.run {
                        guard let idx = self.devices.firstIndex(where: { $0.id == discovered.id }) else { return }
                        let node = FileNode(name: name, isFolder: true, modified: Date(), remotePath: childRef, isLoaded: true)
                        self.devices[idx].addNode(node, toParent: folder.id)
                        self.selection = [node.id]
                        self.anchorID = node.id
                    }
                } catch {
                    await MainActor.run {
                        self.showToast("Couldn't create folder: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        let node = FileNode(name: name, isFolder: true, modified: Date())
        devices[idx].addNode(node, toParent: folder.id)
        selection = [node.id]
        anchorID = node.id
    }

    // MARK: Delete

    func requestDelete() {
        guard let device = currentDevice, !selectedNodes.isEmpty else { return }
        pendingDelete = PendingDelete(nodes: selectedNodes, deviceName: device.name)
        if settings.confirmBeforeDeleting {
            showDeleteSheet = true
        } else {
            performDelete()
        }
    }

    func cancelDeleteSheet() {
        showDeleteSheet = false
        pendingDelete = nil
    }

    func confirmDelete() {
        showDeleteSheet = false
        performDelete()
    }

    private func performDelete() {
        guard let idx = currentDeviceIndex, let pending = pendingDelete else { return }
        let ids = Set(pending.nodes.map(\.id))
        let count = pending.nodes.count
        let deviceName = devices[idx].name

        if let discovered = devices[idx].discovered, let backend = backend(for: devices[idx]) {
            let remotePaths = pending.nodes.compactMap(\.remotePath)
            pendingDelete = nil
            Task {
                do {
                    try await backend.delete(discovered, paths: remotePaths)
                    await MainActor.run {
                        guard let idx = self.devices.firstIndex(where: { $0.id == discovered.id }) else { return }
                        self.devices[idx].removeNodes(ids: ids)
                        self.selection.subtract(ids)
                        self.showToast("Deleted \(count) item\(count == 1 ? "" : "s") from \(deviceName)")
                    }
                } catch {
                    await MainActor.run {
                        self.showToast("Couldn't delete from \(deviceName): \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        devices[idx].removeNodes(ids: ids)
        selection.subtract(ids)
        pendingDelete = nil
        showToast("Deleted \(count) item\(count == 1 ? "" : "s") from \(deviceName)")
    }

    // MARK: Transfers — pull / push / backup

    func pullSelectionToMac() {
        guard let device = currentDevice, !selectedNodes.isEmpty else { return }
        for node in selectedNodes {
            let size = device.size(of: node)
            transferQueue.enqueue(Transfer(
                direction: .pull,
                name: node.name,
                totalBytes: max(size, 1),
                deviceID: device.id,
                deviceName: device.name,
                destinationDescription: settings.pullDestination,
                sourceNodeID: node.id,
                isReal: device.isRemoteBacked
            ))
        }
        showToast("Pulling \(selectedNodes.count) item\(selectedNodes.count == 1 ? "" : "s") to Mac")
        processRealTransfersIfNeeded()
    }

    func presentPushPicker() {
        guard let device = currentDevice, let folder = currentFolder else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Push"
        panel.message = "Choose files to copy to \"\(folder.name)\" on \(device.name)"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            pushFile(from: url, into: folder.id)
        }
    }

    func pushFile(from url: URL, into folderID: UUID) {
        guard let device = currentDevice else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 1_000_000
        transferQueue.enqueue(Transfer(
            direction: .push,
            name: url.lastPathComponent,
            totalBytes: max(size, 1),
            deviceID: device.id,
            deviceName: device.name,
            destinationDescription: "\"\(currentFolder?.name ?? device.name)\" on \(device.name)",
            targetFolderID: folderID,
            localURL: url,
            isReal: device.isRemoteBacked
        ))
        showToast("Copying \(url.lastPathComponent) to device")
        processRealTransfersIfNeeded()
    }

    // MARK: Real transfer runner (ADB/MTP/SD, one at a time)

    /// Drives transfers marked `isReal`: `TransferQueue`'s own timer only simulates
    /// progress for the sample-data demo, so real backends are advanced from here.
    func processRealTransfersIfNeeded() {
        guard !isProcessingRealTransfer else { return }
        guard let idx = transferQueue.items.firstIndex(where: { $0.isReal && $0.status == .waiting }) else { return }
        guard !transferQueue.items.contains(where: { $0.status == .active }) else { return }

        isProcessingRealTransfer = true
        transferQueue.items[idx].status = .active
        let transfer = transferQueue.items[idx]

        let progress = TransferProgress()
        activeTransferProgress = progress
        let startTime = Date()
        progress.onProgress = { [weak self] doneBytes in
            Task { @MainActor [weak self] in
                self?.updateRealTransferProgress(transferID: transfer.id, doneBytes: doneBytes, startTime: startTime)
            }
        }

        Task {
            do {
                let resultRef = try await performRealTransfer(transfer, progress: progress)
                await MainActor.run {
                    self.finishRealTransfer(transfer, resultRef: resultRef, succeeded: true)
                }
            } catch is TransferCancelledError {
                await MainActor.run {
                    self.finishRealTransfer(transfer, resultRef: nil, succeeded: false)
                }
            } catch {
                await MainActor.run {
                    self.showToast("\(transfer.name) failed: \(error.localizedDescription)")
                    self.finishRealTransfer(transfer, resultRef: nil, succeeded: false)
                }
            }
        }
    }

    private func updateRealTransferProgress(transferID: Transfer.ID, doneBytes: Int64, startTime: Date) {
        guard let i = transferQueue.items.firstIndex(where: { $0.id == transferID }), transferQueue.items[i].status == .active else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        transferQueue.items[i].doneBytes = min(doneBytes, transferQueue.items[i].totalBytes)
        transferQueue.items[i].speedBytesPerSecond = elapsed > 0 ? Int64(Double(doneBytes) / elapsed) : 0
    }

    /// Stops the x-button's transfer outright rather than just hiding it: for the
    /// one real transfer currently in flight, this reaches into whichever backend
    /// is running it (kills the `adb` process, aborts the libmtp call, stops a
    /// chunked copy) via `activeTransferProgress`, instead of leaving it to finish
    /// unobserved in the background. A still-queued transfer just never starts.
    func cancelTransfer(_ id: Transfer.ID) {
        guard let idx = transferQueue.items.firstIndex(where: { $0.id == id }) else { return }
        let transfer = transferQueue.items[idx]
        guard transfer.status == .waiting || transfer.status == .active else { return }

        if transfer.status == .active, transfer.isReal {
            activeTransferProgress?.cancel()
        }
        transferQueue.items[idx].status = .cancelled
        transferQueue.items[idx].speedBytesPerSecond = 0
    }

    /// Returns the new item's reference for a push, so `handleTransferComplete` can
    /// label the new `FileNode` correctly without re-deriving a backend-specific path.
    private func finishRealTransfer(_ transfer: Transfer, resultRef: String?, succeeded: Bool) {
        guard let i = transferQueue.items.firstIndex(where: { $0.id == transfer.id }) else {
            isProcessingRealTransfer = false
            activeTransferProgress = nil
            processRealTransfersIfNeeded()
            return
        }
        // `cancelTransfer` may already have set this to `.cancelled` while the
        // backend call above was still unwinding — don't let a late "succeeded"
        // stomp back over the user's own cancel.
        let wasCancelledByUser = transferQueue.items[i].status == .cancelled
        if !wasCancelledByUser {
            transferQueue.items[i].doneBytes = succeeded ? transfer.totalBytes : transferQueue.items[i].doneBytes
            transferQueue.items[i].status = succeeded ? .done : .cancelled
        }
        isProcessingRealTransfer = false
        activeTransferProgress = nil
        if succeeded, !wasCancelledByUser {
            var completed = transfer
            completed.resultRef = resultRef
            handleTransferComplete(completed)
        }
        processRealTransfersIfNeeded()
    }

    private func performRealTransfer(_ transfer: Transfer, progress: TransferProgress) async throws -> String? {
        guard let device = devices.first(where: { $0.id == transfer.deviceID }), let discovered = device.discovered, let backend = backend(for: device) else {
            throw ShellError.nonZeroExit(1, "\(transfer.deviceName) is no longer connected.")
        }
        switch transfer.direction {
        case .pull:
            guard let nodeID = transfer.sourceNodeID, let node = device.node(nodeID), let remotePath = node.remotePath else {
                throw ShellError.nonZeroExit(1, "Couldn't find \(transfer.name) on the device anymore.")
            }
            let destDir = (settings.pullDestination as NSString).expandingTildeInPath
            try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            let localURL = URL(fileURLWithPath: destDir).appendingPathComponent(node.name)
            try await backend.pull(discovered, remotePath: remotePath, to: localURL, progress: progress)
            return nil
        case .push:
            guard let localURL = transfer.localURL, let folderID = transfer.targetFolderID,
                  let folder = device.node(folderID), let parentPath = folder.remotePath else {
                throw ShellError.nonZeroExit(1, "Couldn't find the destination folder on the device.")
            }
            return try await backend.push(discovered, localURL: localURL, parentPath: parentPath, progress: progress)
        case .backup:
            throw ShellError.nonZeroExit(1, "Backup isn't implemented for this device yet.")
        }
    }

    func backupNow() {
        guard let device = currentDevice else { return }
        var total: Int64 = 0
        if backupIncludePhotos { total += device.categories.first { $0.name == "Photos & Videos" }?.bytes ?? 0 }
        if backupIncludeDocuments { total += device.categories.first { $0.name == "Documents" }?.bytes ?? 0 }
        if backupIncludeDownloads { total += device.largestFolders.first { $0.name.hasPrefix("Download") }?.bytes ?? 0 }
        if backupIncludeAudio { total += device.categories.first { $0.name == "Audio" }?.bytes ?? 0 }
        guard total > 0, activeBackupTransfer == nil else { return }
        transferQueue.enqueue(Transfer(
            direction: .backup,
            name: "Backup of \(device.name)",
            totalBytes: total,
            deviceID: device.id,
            deviceName: device.name,
            destinationDescription: "~/Backups/Android/\(device.name)"
        ))
    }

    func handleTransferComplete(_ transfer: Transfer) {
        switch transfer.direction {
        case .pull:
            if let nodeID = transfer.sourceNodeID,
               let device = devices.first(where: { $0.id == transfer.deviceID }),
               let sourceNode = device.node(nodeID) {
                macFiles.insert((UUID(), sourceNode.name, transfer.totalBytes, true), at: 0)
            }
            showToast("Saved to \(settings.pullDestination)")
        case .push:
            if let idx = devices.firstIndex(where: { $0.id == transfer.deviceID }), let folderID = transfer.targetFolderID {
                let node = FileNode(
                    name: transfer.name, isFolder: false, size: transfer.totalBytes, modified: Date(),
                    remotePath: transfer.resultRef, isLoaded: true
                )
                devices[idx].addNode(node, toParent: folderID)
            }
            showToast("Copied to device")
        case .backup:
            if let idx = devices.firstIndex(where: { $0.id == transfer.deviceID }) {
                let now = Format.date(Date())
                devices[idx].lastBackup = now
            }
            showToast("Backup complete")
        }
    }

    // MARK: Connect / eject

    func beginConnecting() {
        connecting = true
        switch connectMethod {
        case .adb, .wifi:
            Task { await self.connectRealADBDevice() }
        case .sd:
            Task { await self.connectRealSDDevice() }
        case .usb:
            Task { await self.connectRealMTPDevice() }
        }
    }

    /// USB "File Transfer" (MTP) mode, via the bundled `libmtp` bridge.
    private func connectRealMTPDevice() async {
        do {
            let known = Set(devices.compactMap(\.discovered?.id))
            let found = try await mtpBackend.discoverDevices()
            guard let next = found.first(where: { !known.contains($0.id) }) else {
                throw ShellError.nonZeroExit(1, "No MTP device found. Connect the phone by cable and set it to File Transfer mode.")
            }
            let rootRef = try await mtpBackend.rootReference(next)
            let rootID = UUID()
            let root = FileNode(id: rootID, name: "Internal storage", isFolder: true, modified: Date(), remotePath: rootRef, isLoaded: false)
            var device = Device(
                id: next.id, name: next.displayName, model: next.model, connection: .usb,
                capacity: 0, lastBackup: "Never", categories: [], largestFolders: [],
                nodes: [rootID: root], rootID: rootID, discovered: next
            )
            if let info = try? await mtpBackend.storageInfo(next, path: rootRef) {
                device.capacity = info.totalBytes
                device.categories = [StorageCategory(name: "Used", bytes: info.usedBytes, colorHex: "0A84FF")]
            }
            await MainActor.run {
                self.connecting = false
                self.devices.append(device)
                self.selectDevice(device.id)
                self.showToast("Connected to \(device.name)")
            }
        } catch {
            await MainActor.run {
                self.connecting = false
                self.showToast("Couldn't connect: \(error.localizedDescription)")
            }
        }
    }

    /// Covers a card already inserted before the Connect Device screen was opened;
    /// one inserted afterwards is picked up automatically (see `AppState+RemovableVolumes`).
    private func connectRealSDDevice() async {
        do {
            let known = Set(devices.compactMap(\.discovered?.id))
            let found = try await volumeBackend.discoverDevices()
            guard let next = found.first(where: { !known.contains($0.id) }) else {
                throw ShellError.nonZeroExit(1, "No SD card found. Insert one into this Mac's slot or a USB card reader.")
            }
            await addSDDevice(next)
            await MainActor.run { self.connecting = false }
        } catch {
            await MainActor.run {
                self.connecting = false
                self.showToast("Couldn't connect: \(error.localizedDescription)")
            }
        }
    }

    /// USB debugging or Wireless debugging, talking to the real `adb` the user has installed.
    private func connectRealADBDevice() async {
        do {
            let discovered: DiscoveredDevice
            if connectMethod == .wifi {
                guard !wifiAddress.isEmpty else {
                    throw ShellError.nonZeroExit(1, "Enter the device's IP address and port.")
                }
                discovered = try await adbBackend.connect(address: wifiAddress, pairingCode: wifiCode.isEmpty ? nil : wifiCode)
            } else {
                let known = Set(devices.compactMap(\.discovered?.id))
                let found = try await adbBackend.discoverDevices()
                guard let next = found.first(where: { !known.contains($0.id) }) else {
                    throw ShellError.nonZeroExit(1, "No new ADB device found. Make sure USB debugging is on and you tapped Allow on the phone.")
                }
                discovered = next
            }

            var device = makeRemoteDevice(from: discovered)
            if let info = try? await adbBackend.storageInfo(discovered, path: "/sdcard") {
                device.capacity = info.totalBytes
                device.categories = [StorageCategory(name: "Used", bytes: info.usedBytes, colorHex: "0A84FF")]
            }

            await MainActor.run {
                self.connecting = false
                self.devices.append(device)
                self.selectDevice(device.id)
                self.showToast("Connected to \(device.name)")
            }
        } catch {
            await MainActor.run {
                self.connecting = false
                self.showToast("Couldn't connect: \(error.localizedDescription)")
            }
        }
    }

    private func makeRemoteDevice(from discovered: DiscoveredDevice) -> Device {
        let rootID = UUID()
        let root = FileNode(id: rootID, name: "Internal storage", isFolder: true, modified: Date(), remotePath: "/sdcard", isLoaded: false)
        return Device(
            id: discovered.id,
            name: discovered.displayName,
            model: discovered.model,
            connection: discovered.isWireless ? .wifi : .adb,
            capacity: 0,
            lastBackup: "Never",
            categories: [],
            largestFolders: [],
            nodes: [rootID: root],
            rootID: rootID,
            discovered: discovered
        )
    }

    func ejectDevice(_ id: Device.ID) {
        guard let device = devices.first(where: { $0.id == id }) else { return }
        if device.connection == .sd, let path = device.discovered?.serial {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: path))
        } else if device.connection == .usb, let discovered = device.discovered {
            mtpBackend.disconnect(discovered)
        }
        removeDeviceFromState(id, toastText: "\"\(device.name)\" can be safely unplugged")
    }

    /// Drops a device from state (cancelling its in-flight transfers) and shows a toast.
    /// Shared by the manual Eject button and the automatic unmount notification.
    func removeDeviceFromState(_ id: Device.ID, toastText: String) {
        guard devices.contains(where: { $0.id == id }) else { return }
        transferQueue.items = transferQueue.items.map { transfer in
            var t = transfer
            if t.deviceID == id, t.status == .waiting || t.status == .active { t.status = .cancelled }
            return t
        }
        devices.removeAll { $0.id == id }
        if selectedDeviceID == id {
            if let next = devices.first {
                selectDevice(next.id)
            } else {
                selectedDeviceID = nil
                screen = .connect
            }
        }
        showToast(toastText)
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toastDismissTask?.cancel()
        toast = ToastMessage(text: text)
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
