import SwiftUI

struct FileKindInfo {
    var label: String
    var color: Color
    var isMedia: Bool
    var extensionLabel: String
}

enum FileKind {
    private static let table: [String: (label: String, hex: String, media: Bool)] = [
        "jpg": ("JPEG image", "ff9f0a", true),
        "jpeg": ("JPEG image", "ff9f0a", true),
        "png": ("PNG image", "ff9f0a", true),
        "cr3": ("Canon RAW image", "ff9f0a", true),
        "mp4": ("MPEG-4 movie", "bf5af2", true),
        "mov": ("QuickTime movie", "bf5af2", true),
        "mp3": ("MP3 audio", "ff375f", false),
        "m4a": ("MPEG-4 audio", "ff375f", false),
        "pdf": ("PDF document", "ff3b30", false),
        "xlsx": ("Excel spreadsheet", "30b158", false),
        "txt": ("Plain text", "8e8e93", false),
        "apk": ("Android package", "34c759", false),
        "zip": ("ZIP archive", "8e8e93", false),
        "vcf": ("vCard", "0a84ff", false),
    ]

    static func info(forName name: String, isFolder: Bool) -> FileKindInfo {
        if isFolder {
            return FileKindInfo(label: "Folder", color: Color(hex: "4aa8f8"), isMedia: false, extensionLabel: "")
        }
        let ext = (name as NSString).pathExtension.lowercased()
        let entry = table[ext] ?? ("Document", "8e8e93", false)
        let extLabel = ext.isEmpty ? "FILE" : String(ext.uppercased().prefix(4))
        return FileKindInfo(label: entry.label, color: Color(hex: entry.hex), isMedia: entry.media, extensionLabel: extLabel)
    }

    static func symbolName(forName name: String, isFolder: Bool) -> String {
        if isFolder { return "folder.fill" }
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "cr3": return "photo.fill"
        case "mp4", "mov": return "film.fill"
        case "mp3", "m4a": return "music.note"
        case "pdf": return "doc.richtext.fill"
        case "xlsx": return "tablecells.fill"
        case "apk": return "shippingbox.fill"
        case "zip": return "doc.zipper"
        case "vcf": return "person.crop.square.fill"
        default: return "doc.fill"
        }
    }
}

extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
