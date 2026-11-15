import Foundation

/// Calendar maths on "yyyy-MM-dd" day strings, in the proleptic Gregorian calendar with no time zone involved.
enum TaskDates {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// True for a real calendar day written "yyyy-MM-dd".
    static func isValid(_ iso: String) -> Bool { parse(iso) != nil }

    /// `iso` moved by `days`, or nil when `iso` is not a day.
    static func adding(days: Int, to iso: String) -> String? {
        guard let start = parse(iso), let moved = calendar.date(byAdding: .day, value: days, to: start) else {
            return nil
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func parse(_ iso: String) -> Date? {
        let pieces = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
            let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2])
        else { return nil }
        let parts = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: parts) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day ? date : nil
    }
}
