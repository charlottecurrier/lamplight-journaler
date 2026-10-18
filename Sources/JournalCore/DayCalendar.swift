import Foundation

/// A calendar day with no time or time zone attached.
struct DayStamp: Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Days since 1970-01-01. Handy for "is this the next day?" checks.
    var dayNumber: Int { DayMath.daysFromCivil(year, month, day) }

    init(dayNumber: Int) {
        let (y, m, d) = DayMath.civilFromDays(dayNumber)
        self.init(year: y, month: m, day: d)
    }

    func adding(days: Int) -> DayStamp { DayStamp(dayNumber: dayNumber + days) }

    static func < (lhs: DayStamp, rhs: DayStamp) -> Bool { lhs.dayNumber < rhs.dayNumber }
}

/// Decides which calendar day an entry belongs to.
///
/// Someone who writes at 12:40 AM is usually still finishing "yesterday".
/// `rolloverHour` moves the start of the day later, so that entry (and the streak) stays with yesterday.
struct DayCalendar: Equatable {
    var rolloverHour: Int

    init(rolloverHour: Int = 0) {
        self.rolloverHour = min(max(rolloverHour, 0), 12)
    }

    func stamp(for date: Date, timeZone: TimeZone) -> DayStamp {
        let shifted = date.addingTimeInterval(-Double(rolloverHour) * 3600)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: shifted)
        return DayStamp(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }
}

/// Civil date math (Howard Hinnant's algorithms). Pure integers, same answer on every platform.
enum DayMath {
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}
