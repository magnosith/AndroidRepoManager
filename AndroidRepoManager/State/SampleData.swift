import Foundation

/// Builds the fake devices/file trees used before the real ADB/MTP/SD backends exist.
/// Mirrors the seed data in `design_handoff_android_repo_manager/RepoManagerWindow.dc.html`.
struct SampleDataBuilder {
    private var nodes: [UUID: FileNode] = [:]
    private var seed: UInt64 = 7
    private let base = Self.makeDate(year: 2026, month: 10, day: 27, hour: 9, minute: 41)

    static func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return Calendar.current.date(from: comps) ?? Date()
    }

    private mutating func rnd() -> Double {
        seed = (seed &* 16807) % 2_147_483_647
        return Double(seed) / 2_147_483_647
    }

    private mutating func ago(daysAgo: Double?) -> Date {
        let days = daysAgo ?? (rnd() * 40)
        let seconds = days * 86400 + rnd() * 3600
        return base.addingTimeInterval(-seconds)
    }

    private mutating func file(_ name: String, _ size: Int64, daysAgo: Double? = nil) -> FileNode {
        FileNode(name: name, isFolder: false, size: size, modified: ago(daysAgo: daysAgo))
    }

    private mutating func file(_ name: String, _ size: Int64, at date: Date) -> FileNode {
        FileNode(name: name, isFolder: false, size: size, modified: date)
    }

    private mutating func folder(_ name: String, _ children: [FileNode], daysAgo: Double? = nil) -> FileNode {
        var node = FileNode(name: name, isFolder: true, modified: ago(daysAgo: daysAgo))
        var childIDs: [UUID] = []
        for child in children {
            var c = child
            c.parentID = node.id
            nodes[c.id] = c
            childIDs.append(c.id)
        }
        node.childIDs = childIDs
        nodes[node.id] = node
        return node
    }

    private mutating func shots(prefix: String, count: Int, ext: String, minSize: Double, maxSize: Double) -> [FileNode] {
        var out: [FileNode] = []
        var ts = Self.makeDate(year: 2026, month: 10, day: 26, hour: 18, minute: 4, second: 12).timeIntervalSince1970
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        for _ in 0..<count {
            ts -= (30_000 + rnd() * 110_000)
            let date = Date(timeIntervalSince1970: ts)
            let name = "\(prefix)\(df.string(from: date)).\(ext)"
            let size = Int64(minSize + rnd() * (maxSize - minSize))
            out.append(file(name, size, at: date))
        }
        return out
    }

    private mutating func finish(root: FileNode) -> (rootID: UUID, nodes: [UUID: FileNode]) {
        (root.id, nodes)
    }

    // MARK: Pixel 9 Pro (USB · MTP)

    mutating func buildPixel() -> Device {
        nodes = [:]
        seed = 7
        let root = folder("Internal storage", [
            folder(".thumbnails", [file(".database_uuid", 36), file("1698123.jpg", 18_200)]),
            folder("Alarms", []),
            folder("Android", [
                folder("data", [folder("com.google.android.apps.photos", []), folder("com.spotify.music", [])]),
                folder("media", []),
                folder("obb", []),
            ]),
            folder("DCIM", [
                folder("Camera", shots(prefix: "PXL_", count: 16, ext: "jpg", minSize: 2.1e6, maxSize: 6.8e6)
                    + shots(prefix: "PXL_", count: 3, ext: "mp4", minSize: 84e6, maxSize: 420e6), daysAgo: 1),
                folder("Screenshots", shots(prefix: "Screenshot_", count: 6, ext: "png", minSize: 380e3, maxSize: 1.6e6)),
            ], daysAgo: 1),
            folder("Documents", [
                folder("Contracts", [file("NDA_Northwind.pdf", 184_000), file("Lease_Agreement_2026.pdf", 2_400_000)]),
                file("Budget 2026.xlsx", 86_000),
                file("Meeting notes.txt", 4_200),
                file("Resume_2026.pdf", 212_000),
                file("Passport scan.jpg", 3_100_000),
            ]),
            folder("Download", [
                file("invoice_oct_2026.pdf", 214_000, daysAgo: 2),
                file("app-release.apk", 48_200_000),
                file("Podcast_Ep42.mp3", 62_400_000),
                file("photos_backup.zip", 1_120_000_000),
                file("boarding_pass.pdf", 96_000, daysAgo: 0),
                file("wallpaper_4k.png", 8_400_000),
            ], daysAgo: 0),
            folder("Movies", [file("Recital.mp4", 1_800_000_000), file("Timelapse_Lisbon.mp4", 412_000_000)]),
            folder("Music", [
                folder("Albums", [file("01 Opening.mp3", 8_200_000), file("02 Harbor Lights.mp3", 9_100_000), file("03 Slow Tide.mp3", 7_400_000)]),
                file("Voice memo 14.m4a", 3_200_000),
            ]),
            folder("Pictures", [
                folder("WhatsApp Images", shots(prefix: "IMG-", count: 8, ext: "jpg", minSize: 120e3, maxSize: 480e3)),
                folder("Instagram", shots(prefix: "IMG_", count: 5, ext: "jpg", minSize: 900e3, maxSize: 2.4e6)),
            ]),
            folder("Recordings", [file("Interview_Oct21.m4a", 41_000_000), file("Lecture_03.m4a", 88_000_000)]),
            file(".nomedia", 0),
        ], daysAgo: 0)
        let (rootID, allNodes) = finish(root: root)
        return Device(
            id: "pixel",
            name: "Pixel 9 Pro",
            model: "Google · Android 16",
            connection: .usb,
            capacity: 256_000_000_000,
            lastBackup: "Oct 19, 2026 at 8:12 PM",
            categories: [
                StorageCategory(name: "Photos & Videos", bytes: 96_400_000_000, colorHex: "0A84FF"),
                StorageCategory(name: "Apps", bytes: 38_100_000_000, colorHex: "30D158"),
                StorageCategory(name: "Audio", bytes: 9_800_000_000, colorHex: "FF9F0A"),
                StorageCategory(name: "Documents", bytes: 4_600_000_000, colorHex: "BF5AF2"),
                StorageCategory(name: "System", bytes: 22_500_000_000, colorHex: "8E8E93"),
            ],
            largestFolders: [
                LargestFolder(name: "DCIM", bytes: 71_200_000_000),
                LargestFolder(name: "Android", bytes: 38_100_000_000),
                LargestFolder(name: "Movies", bytes: 24_800_000_000),
                LargestFolder(name: "Music", bytes: 9_100_000_000),
                LargestFolder(name: "Download", bytes: 6_300_000_000),
                LargestFolder(name: "Pictures", bytes: 3_400_000_000),
            ],
            nodes: allNodes,
            rootID: rootID
        )
    }

    // MARK: Galaxy S25 Ultra (Wi‑Fi · ADB)

    mutating func buildGalaxy() -> Device {
        nodes = [:]
        seed = 42
        let root = folder("Internal storage", [
            folder("Android", [folder("data", []), folder("obb", [])]),
            folder("DCIM", [
                folder("Camera", shots(prefix: "", count: 14, ext: "jpg", minSize: 3.2e6, maxSize: 9.4e6)
                    + shots(prefix: "", count: 2, ext: "mp4", minSize: 140e6, maxSize: 880e6), daysAgo: 2),
            ], daysAgo: 2),
            folder("Documents", [file("Travel itinerary.pdf", 340_000), file("Tax return 2025.pdf", 1_400_000)]),
            folder("Download", [file("SamsungNotes_export.zip", 22_000_000), file("menu.pdf", 610_000), file("firmware_notes.txt", 3_100)]),
            folder("Movies", [file("Drone_Coast.mp4", 2_300_000_000)]),
            folder("Music", [file("Morning Run.mp3", 6_600_000), file("Focus Mix.mp3", 74_000_000)]),
            folder("Pictures", [folder("Screenshots", shots(prefix: "Screenshot_", count: 7, ext: "png", minSize: 400e3, maxSize: 1.9e6))]),
        ], daysAgo: 1)
        let (rootID, allNodes) = finish(root: root)
        return Device(
            id: "galaxy",
            name: "Galaxy S25 Ultra",
            model: "Samsung · Android 16",
            connection: .wifi,
            capacity: 512_000_000_000,
            lastBackup: "Never",
            categories: [
                StorageCategory(name: "Photos & Videos", bytes: 188_000_000_000, colorHex: "0A84FF"),
                StorageCategory(name: "Apps", bytes: 62_000_000_000, colorHex: "30D158"),
                StorageCategory(name: "Audio", bytes: 21_000_000_000, colorHex: "FF9F0A"),
                StorageCategory(name: "Documents", bytes: 8_400_000_000, colorHex: "BF5AF2"),
                StorageCategory(name: "System", bytes: 26_000_000_000, colorHex: "8E8E93"),
            ],
            largestFolders: [
                LargestFolder(name: "DCIM", bytes: 172_000_000_000),
                LargestFolder(name: "Android", bytes: 62_000_000_000),
                LargestFolder(name: "Music", bytes: 20_400_000_000),
                LargestFolder(name: "Movies", bytes: 16_000_000_000),
                LargestFolder(name: "Download", bytes: 3_100_000_000),
                LargestFolder(name: "Documents", bytes: 2_200_000_000),
            ],
            nodes: allNodes,
            rootID: rootID
        )
    }

    // MARK: SanDisk Extreme (SD Card Reader)

    mutating func buildSDCard() -> Device {
        nodes = [:]
        seed = 99
        let root = folder("SD card", [
            folder("DCIM", [folder("100CANON", shots(prefix: "IMG_", count: 12, ext: "cr3", minSize: 24e6, maxSize: 32e6), daysAgo: 5)], daysAgo: 5),
            folder("Backups", [file("pixel_backup_2025.zip", 4_200_000_000), file("contacts.vcf", 88_000)]),
            folder("Music", [file("Live at the Lantern.mp3", 112_000_000)]),
        ], daysAgo: 5)
        let (rootID, allNodes) = finish(root: root)
        return Device(
            id: "sd",
            name: "SanDisk Extreme",
            model: "microSD · exFAT",
            connection: .sd,
            capacity: 128_000_000_000,
            lastBackup: "Sep 30, 2026 at 6:05 PM",
            categories: [
                StorageCategory(name: "Photos & Videos", bytes: 49_800_000_000, colorHex: "0A84FF"),
                StorageCategory(name: "Apps", bytes: 0, colorHex: "30D158"),
                StorageCategory(name: "Audio", bytes: 3_100_000_000, colorHex: "FF9F0A"),
                StorageCategory(name: "Documents", bytes: 4_300_000_000, colorHex: "BF5AF2"),
                StorageCategory(name: "System", bytes: 400_000_000, colorHex: "8E8E93"),
            ],
            largestFolders: [
                LargestFolder(name: "DCIM", bytes: 49_800_000_000),
                LargestFolder(name: "Backups", bytes: 4_300_000_000),
                LargestFolder(name: "Music", bytes: 3_100_000_000),
            ],
            nodes: allNodes,
            rootID: rootID
        )
    }
}

enum SampleData {
    static func devices() -> [Device] {
        var builder = SampleDataBuilder()
        return [builder.buildPixel(), builder.buildGalaxy(), builder.buildSDCard()]
    }

    static func macDownloadsFiles() -> [(name: String, size: Int64)] {
        [
            ("Vacation 2026.mov", 1_240_000_000),
            ("Quarterly Report.pdf", 2_100_000),
            ("Playlist Mix.mp3", 9_600_000),
            ("Wallpaper 6K.png", 14_200_000),
            ("Tickets.pdf", 182_000),
            ("App build 4.2.apk", 52_400_000),
            ("Recipes.txt", 6_100),
            ("Portfolio.zip", 412_000_000),
        ]
    }
}
