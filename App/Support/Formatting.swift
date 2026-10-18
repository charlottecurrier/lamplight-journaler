import Foundation

extension Calendar {
    /// The calendar the journal counts days with. Entries are stamped with Gregorian years no matter which
    /// calendar the device shows, so month grids must use the same one. Only the first weekday follows the device.
    static var journal: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = Calendar.current.firstWeekday
        calendar.locale = Calendar.current.locale
        return calendar
    }
}

/// Date text for an entry, always in the time zone the entry was written in.
enum Fmt {
    private static func style(_ entry: Entry) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: entry.timeZone)
    }

    /// "Friday, October 17, 2026"
    static func fullDate(_ entry: Entry) -> String {
        entry.createdAt.formatted(style(entry).weekday(.wide).month(.wide).day().year())
    }

    /// "9:14 PM"
    static func time(_ entry: Entry) -> String {
        entry.createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: entry.timeZone))
    }

    /// "FRI"
    static func weekdayShort(_ entry: Entry) -> String {
        entry.createdAt.formatted(style(entry).weekday(.abbreviated)).uppercased()
    }

    /// "17"
    static func dayNumber(_ entry: Entry) -> String {
        entry.createdAt.formatted(style(entry).day())
    }

    /// "October 2026"
    static func monthYear(_ entry: Entry) -> String {
        entry.createdAt.formatted(style(entry).month(.wide).year())
    }

    /// "Oct 17, 2026"
    static func shortDate(_ entry: Entry) -> String {
        entry.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: entry.timeZone))
    }

    /// "October 2026" for a calendar page.
    static func monthYear(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(calendar: .journal).month(.wide).year())
    }

    /// Days left before something in Recently Deleted is removed for good.
    static func daysLeft(deletedAt: Date, now: Date = Date(), keepDays: Int = 30) -> Int {
        let elapsed = Int(now.timeIntervalSince(deletedAt) / 86_400)
        return max(0, keepDays - elapsed)
    }
}
