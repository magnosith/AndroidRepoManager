import Foundation

enum ConnectionKind: String, CaseIterable, Hashable, Identifiable {
    case usb, adb, wifi, sd

    var id: String { rawValue }

    /// Short label used on the onboarding method cards ("USB", "ADB", "Wi‑Fi", "SD Card").
    var cardTitle: String {
        switch self {
        case .usb: return "USB"
        case .adb: return "ADB"
        case .wifi: return "Wi‑Fi"
        case .sd: return "SD Card"
        }
    }

    var cardSubtitle: String {
        switch self {
        case .usb: return "MTP file transfer"
        case .adb: return "USB debugging"
        case .wifi: return "Wireless debugging"
        case .sd: return "Card reader"
        }
    }

    /// Sidebar sub-line, e.g. "USB · MTP".
    var connectionLabel: String {
        switch self {
        case .usb: return "USB · MTP"
        case .adb: return "USB · ADB"
        case .wifi: return "Wi‑Fi · ADB"
        case .sd: return "SD Card Reader"
        }
    }

    var symbolName: String {
        switch self {
        case .usb, .adb, .wifi: return "smartphone"
        case .sd: return "sdcard"
        }
    }

    var onboardingSteps: [String] {
        switch self {
        case .usb:
            return [
                "Connect your phone to this Mac with a USB‑C cable.",
                "Unlock the phone.",
                "Open the \"Charging this device via USB\" notification and choose File transfer.",
            ]
        case .adb:
            return [
                "On the phone, open Settings › About phone and tap Build number seven times.",
                "In Developer options, turn on USB debugging.",
                "Connect by cable and tap Allow when asked to trust this Mac's RSA key.",
            ]
        case .wifi:
            return [
                "Make sure the phone and this Mac are on the same network.",
                "In Developer options, open Wireless debugging.",
                "Tap Pair device with pairing code, then enter the address and code below.",
            ]
        case .sd:
            return [
                "Insert the card into your Mac's SD slot or a USB card reader.",
                "The card appears under Devices as soon as it mounts.",
                "exFAT and FAT32 cards can be read and written.",
            ]
        }
    }

    var instructionsTitle: String {
        switch self {
        case .usb: return "Connect via USB"
        case .adb: return "Connect via ADB"
        case .wifi: return "Connect via Wi‑Fi"
        case .sd: return "Connect an SD Card"
        }
    }
}

enum ViewMode: String {
    case list, grid
}

enum Screen: Hashable {
    case browser
    case storage
    case connect
}

enum SortKey: String, CaseIterable {
    case name, date, size, kind

    var title: String {
        switch self {
        case .name: return "Name"
        case .date: return "Date Modified"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }
}

enum ConflictPolicy: String, CaseIterable, Identifiable {
    case ask = "Ask"
    case replace = "Replace"
    case keepBoth = "Keep Both"
    var id: String { rawValue }
}

enum DefaultViewOption: String, CaseIterable, Identifiable {
    case list = "List"
    case grid = "Grid"
    var id: String { rawValue }
}
