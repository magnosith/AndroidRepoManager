import Foundation

/// Talks to Android phones connected over USB in "File Transfer" (MTP) mode.
///
/// Unlike ADB and SD cards, macOS has no native framework for this (confirmed by
/// pulling apart Google's own "Android File Transfer.app": it bundles `libmtp.dylib`
/// + `libusb.dylib` and talks raw USB itself — there's no Finder mount to piggyback
/// on). This backend links the same `libmtp` (installed via Homebrew) directly
/// through a bridging header, rather than shelling out to its bundled CLI tools,
/// which address objects by numeric ID with no stable machine-readable output.
///
/// MTP objects don't have paths — they have a 32-bit id plus a storage id. Every
/// `RemoteEntry.path` / `FileNode.remotePath` this backend hands out is the string
/// `"<storageID>:<objectID>"`; `LIBMTP_FILES_AND_FOLDERS_ROOT` (0xFFFFFFFF) is the
/// sentinel object id for a storage's root.
final class MTPFileSystem: DeviceFileSystem {
    private var openDevices: [String: UnsafeMutablePointer<LIBMTP_mtpdevice_t>] = [:]
    private var initialized = false
    private let queue = DispatchQueue(label: "com.androidrepomanager.mtp")

    private func initializeIfNeeded() {
        guard !initialized else { return }
        LIBMTP_Init()
        initialized = true
    }

    private func runOnQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Discovery

    func discoverDevices() async throws -> [DiscoveredDevice] {
        try await runOnQueue { [self] in
            self.initializeIfNeeded()
            var rawList: UnsafeMutablePointer<LIBMTP_raw_device_t>?
            var count: Int32 = 0
            let err = LIBMTP_Detect_Raw_Devices(&rawList, &count)
            guard err == LIBMTP_ERROR_NONE, let rawList, count > 0 else { return [] }
            defer { free(rawList) }

            var results: [DiscoveredDevice] = []
            for i in 0..<Int(count) {
                let rawPtr = rawList + i
                let busKey = "mtp-\(rawPtr.pointee.bus_location)-\(rawPtr.pointee.devnum)"

                let devicePtr: UnsafeMutablePointer<LIBMTP_mtpdevice_t>
                if let existing = self.openDevices[busKey] {
                    devicePtr = existing
                } else if let opened = LIBMTP_Open_Raw_Device_Uncached(rawPtr) {
                    devicePtr = opened
                } else {
                    continue
                }

                let serialNumber = Self.takeCString(LIBMTP_Get_Serialnumber(devicePtr))
                let modelName = Self.takeCString(LIBMTP_Get_Modelname(devicePtr))
                let friendlyName = Self.takeCString(LIBMTP_Get_Friendlyname(devicePtr))
                let serial = (serialNumber?.isEmpty == false) ? serialNumber! : busKey
                let display = (friendlyName?.isEmpty == false) ? friendlyName! : (modelName ?? "Android device")

                self.openDevices[busKey] = devicePtr
                if serial != busKey { self.openDevices[serial] = devicePtr }

                results.append(DiscoveredDevice(
                    id: serial, serial: serial, displayName: display,
                    model: modelName ?? "MTP device", isWireless: false
                ))
            }
            return results
        }
    }

    func connect(address: String, pairingCode: String?) async throws -> DiscoveredDevice {
        throw ShellError.nonZeroExit(1, "MTP devices connect over USB — there's no address to enter.")
    }

    /// Call when a device is ejected, so the USB session is released cleanly.
    func disconnect(_ device: DiscoveredDevice) {
        queue.async { [self] in
            guard let ptr = self.openDevices[device.serial] else { return }
            LIBMTP_Release_Device(ptr)
            self.openDevices = self.openDevices.filter { $0.value != ptr }
        }
    }

    // MARK: Listing

    func list(_ device: DiscoveredDevice, path: String) async throws -> [RemoteEntry] {
        try await runOnQueue { [self] in
            let devicePtr = try self.device(for: device)
            let (storageID, parentID) = Self.parseRef(path)
            var results: [RemoteEntry] = []
            var node = LIBMTP_Get_Files_And_Folders(devicePtr, storageID, parentID)
            while let n = node {
                let f = n.pointee
                let name = f.filename != nil ? String(cString: f.filename) : "Untitled"
                let isDirectory = f.filetype == LIBMTP_FILETYPE_FOLDER
                let modified = Date(timeIntervalSince1970: TimeInterval(f.modificationdate))
                let ref = Self.makeRef(storageID: f.storage_id, objectID: f.item_id)
                results.append(RemoteEntry(name: name, path: ref, isDirectory: isDirectory, size: Int64(f.filesize), modified: modified))
                let next = f.next
                LIBMTP_destroy_file_t(n)
                node = next
            }
            return results
        }
    }

    // MARK: Storage

    func storageInfo(_ device: DiscoveredDevice, path: String) async throws -> RemoteStorageInfo {
        try await runOnQueue { [self] in
            let devicePtr = try self.device(for: device)
            _ = LIBMTP_Get_Storage(devicePtr, Int32(LIBMTP_STORAGE_SORTBY_NOTSORTED))
            guard let storage = devicePtr.pointee.storage else {
                throw ShellError.nonZeroExit(1, "Couldn't read storage info for \(device.displayName).")
            }
            let total = Int64(storage.pointee.MaxCapacity)
            let free = Int64(storage.pointee.FreeSpaceInBytes)
            return RemoteStorageInfo(totalBytes: total, usedBytes: max(0, total - free), freeBytes: free)
        }
    }

    /// The root reference for a device's first storage, e.g. for building its `FileNode` root.
    func rootReference(_ device: DiscoveredDevice) async throws -> String {
        try await runOnQueue { [self] in
            let devicePtr = try self.device(for: device)
            _ = LIBMTP_Get_Storage(devicePtr, Int32(LIBMTP_STORAGE_SORTBY_NOTSORTED))
            let storageID = devicePtr.pointee.storage?.pointee.id ?? 0
            return Self.makeRef(storageID: storageID, objectID: 0xFFFFFFFF)
        }
    }

    // MARK: Transfers

    func pull(_ device: DiscoveredDevice, remotePath: String, to localURL: URL, progress: TransferProgress) async throws {
        try await runOnQueue { [self] in
            let devicePtr = try self.device(for: device)
            let (_, objectID) = Self.parseRef(remotePath)
            let context = Unmanaged.passUnretained(progress).toOpaque()
            let result = localURL.path.withCString { cpath in
                LIBMTP_Get_File_To_File(devicePtr, objectID, cpath, { sent, total, data in
                    MTPFileSystem.progressTrampoline(sent, total, data)
                }, context)
            }
            if progress.isCancelled {
                try? FileManager.default.removeItem(at: localURL)
                throw TransferCancelledError()
            }
            guard result == 0 else {
                throw ShellError.nonZeroExit(1, Self.lastError(devicePtr) ?? "Couldn't download the file.")
            }
        }
    }

    func push(_ device: DiscoveredDevice, localURL: URL, parentPath: String, progress: TransferProgress) async throws -> String {
        try await runOnQueue { [self] in
            let devicePtr = try self.device(for: device)
            let (storageID, parentID) = Self.parseRef(parentPath)
            guard let fileStruct = LIBMTP_new_file_t() else {
                throw ShellError.nonZeroExit(1, "Couldn't prepare the upload.")
            }
            defer { LIBMTP_destroy_file_t(fileStruct) }
            let size = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            fileStruct.pointee.filename = strdup(localURL.lastPathComponent)
            fileStruct.pointee.filesize = UInt64(size ?? 0)
            fileStruct.pointee.parent_id = parentID
            fileStruct.pointee.storage_id = storageID
            fileStruct.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN

            let context = Unmanaged.passUnretained(progress).toOpaque()
            let result = localURL.path.withCString { cpath in
                LIBMTP_Send_File_From_File(devicePtr, cpath, fileStruct, { sent, total, data in
                    MTPFileSystem.progressTrampoline(sent, total, data)
                }, context)
            }
            if progress.isCancelled {
                // Best-effort: whatever landed on the device before the abort is incomplete.
                if fileStruct.pointee.item_id != 0 {
                    LIBMTP_Delete_Object(devicePtr, fileStruct.pointee.item_id)
                }
                throw TransferCancelledError()
            }
            guard result == 0 else {
                throw ShellError.nonZeroExit(1, Self.lastError(devicePtr) ?? "Couldn't upload the file.")
            }
            return Self.makeRef(storageID: storageID, objectID: fileStruct.pointee.item_id)
        }
    }

    /// `LIBMTP_progressfunc_t`: `int(uint64_t sent, uint64_t total, void const *data)`.
    /// Must be a non-capturing function to bridge to a C function pointer — `data` is
    /// how libmtp carries our actual context through, an `Unmanaged<TransferProgress>`
    /// pointer set up by the caller. Returning non-zero tells libmtp to abort the
    /// transfer right there, which is how a mid-flight cancel actually takes effect.
    private nonisolated static func progressTrampoline(_ sent: UInt64, _ total: UInt64, _ data: UnsafeRawPointer?) -> Int32 {
        guard let data else { return 0 }
        let progress = Unmanaged<TransferProgress>.fromOpaque(data).takeUnretainedValue()
        progress.report(Int64(sent))
        return progress.isCancelled ? 1 : 0
    }

    func delete(_ device: DiscoveredDevice, paths: [String]) async throws {
        try await runOnQueue { [self] in
            let devicePtr = try self.device(for: device)
            for ref in paths {
                let (_, objectID) = Self.parseRef(ref)
                let result = LIBMTP_Delete_Object(devicePtr, objectID)
                guard result == 0 else {
                    throw ShellError.nonZeroExit(1, Self.lastError(devicePtr) ?? "Couldn't delete an item.")
                }
            }
        }
    }

    func makeDirectory(_ device: DiscoveredDevice, parentPath: String, name: String) async throws -> String {
        try await runOnQueue { [self] in
            let devicePtr = try self.device(for: device)
            let (storageID, parentID) = Self.parseRef(parentPath)
            let newID = LIBMTP_Create_Folder(devicePtr, strdup(name), parentID, storageID)
            guard newID != 0 else {
                throw ShellError.nonZeroExit(1, Self.lastError(devicePtr) ?? "Couldn't create the folder.")
            }
            return Self.makeRef(storageID: storageID, objectID: newID)
        }
    }

    // MARK: Helpers

    private func device(for discovered: DiscoveredDevice) throws -> UnsafeMutablePointer<LIBMTP_mtpdevice_t> {
        guard let ptr = openDevices[discovered.serial] else {
            throw ShellError.nonZeroExit(1, "\(discovered.displayName) is no longer connected.")
        }
        return ptr
    }

    private static func takeCString(_ cString: UnsafeMutablePointer<CChar>?) -> String? {
        guard let cString else { return nil }
        defer { free(cString) }
        return String(cString: cString)
    }

    private static func lastError(_ devicePtr: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) -> String? {
        guard let stack = LIBMTP_Get_Errorstack(devicePtr) else { return nil }
        let message = stack.pointee.error_text != nil ? String(cString: stack.pointee.error_text) : nil
        LIBMTP_Clear_Errorstack(devicePtr)
        return message
    }

    static func makeRef(storageID: UInt32, objectID: UInt32) -> String {
        "\(storageID):\(objectID)"
    }

    static func parseRef(_ ref: String) -> (storageID: UInt32, objectID: UInt32) {
        let parts = ref.split(separator: ":")
        guard parts.count == 2, let storageID = UInt32(parts[0]), let objectID = UInt32(parts[1]) else {
            return (0, 0xFFFFFFFF)
        }
        return (storageID, objectID)
    }
}
