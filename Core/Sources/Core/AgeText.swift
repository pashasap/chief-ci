import Foundation

/// Dates in words that survive a night: "12:46", "yesterday 22:10", "Thu 12 Nov 22:10".
public enum AgeText {
    private static let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// When `date` was, seen from `now`, in `zone`.
    public static func when(_ date: Date, now: Date, zone: TimeZone) -> String {
        let calendar = calendar(zone)
        let time = InboxRows.clockText(date, in: zone)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "yesterday " + time
        }
        return dayText(date, zone: zone) + " " + time
    }

    /// "Sat 14 Nov" for a moment in `zone`.
    static func dayText(_ date: Date, zone: TimeZone) -> String {
        let parts = calendar(zone).dateComponents([.weekday, .day, .month], from: date)
        let weekday = days[((parts.weekday ?? 1) - 1) % 7]
        return "\(weekday) \(parts.day ?? 0) \(months[((parts.month ?? 1) - 1) % 12])"
    }

    /// "2026-11-14" reads "Sat 14 Nov"; anything else is returned as it is.
    public static func dayHeader(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            let zone = TimeZone(identifier: "UTC"),
            let date = calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        else { return iso }
        return dayText(date, zone: zone)
    }
}
