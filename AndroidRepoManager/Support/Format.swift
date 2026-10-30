import Foundation

enum Format {
    static func size(_ bytes: Int64) -> String {
        if bytes == 0 { return "Zero bytes" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    static func itemCount(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    static func date(_ date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = timeFormatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today at \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday at \(time)"
        }
        return "\(dayFormatter.string(from: date)) at \(time)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
