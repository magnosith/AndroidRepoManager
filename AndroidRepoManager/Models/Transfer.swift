import Foundation

enum TransferDirection: Hashable {
    case pull   // device -> Mac
    case push   // Mac -> device
    case backup // device -> Mac, via Storage & Backup
}

enum TransferStatus: Hashable {
    case waiting
    case active
    case done
    case cancelled
}

struct Transfer: Identifiable, Hashable {
    let id = UUID()
    var direction: TransferDirection
    var name: String
    var totalBytes: Int64
    var doneBytes: Int64 = 0
    var status: TransferStatus = .waiting
    var deviceID: Device.ID
    var deviceName: String
    /// Human readable destination, e.g. "~/Downloads/Android" or "\"Download\" on Pixel 9 Pro".
    var destinationDescription: String
    var speedBytesPerSecond: Int64 = 0
    /// For push/pull of a single node, the source node id (nil for synthetic backup rows).
    var sourceNodeID: UUID?
    /// For push into the device, the folder it lands in.
    var targetFolderID: UUID?
    /// Local file URL: the source for a push, unused for pull/backup.
    var localURL: URL?
    /// Set after a push completes: the new item's own backend reference
    /// (a path for ADB/SD, a "storageID:objectID" pair for MTP).
    var resultRef: String?
    /// True for a transfer carried out by a real `DeviceFileSystem` (e.g. ADB).
    /// Those are driven by `AppState`'s real-transfer runner instead of `TransferQueue`'s
    /// simulated progress ticker.
    var isReal: Bool = false

    var fractionDone: Double {
        guard totalBytes > 0 else { return 1 }
        return min(1, Double(doneBytes) / Double(totalBytes))
    }

    var detailText: String {
        switch status {
        case .waiting:
            return "Waiting…"
        case .cancelled:
            return "Stopped"
        case .done:
            switch direction {
            case .pull: return "Saved to \(destinationDescription)"
            case .push: return "Copied to \(destinationDescription)"
            case .backup: return "Backed up to \(destinationDescription)"
            }
        case .active:
            let speed = Format.size(speedBytesPerSecond) + "/s"
            let remaining = totalBytes - doneBytes
            let seconds = speedBytesPerSecond > 0 ? max(1, Int(Double(remaining) / Double(speedBytesPerSecond))) : 0
            return "\(Format.size(doneBytes)) of \(Format.size(totalBytes)) · \(speed) · \(seconds) s left"
        }
    }
}
