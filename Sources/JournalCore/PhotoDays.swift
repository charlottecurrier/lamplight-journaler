import Foundation

/// One journal day's photos, as a run in a list that goes from the newest photo to the oldest.
struct PhotoDay: Equatable {
    var day: DayStamp
    /// Where the day's first photo is in the list, and how many it has.
    var start: Int
    var count: Int

    var range: Range<Int> { start..<(start + count) }
}

/// Puts photos into journal days, a photo at a time, in the order a library lists them: newest first. A day ends at the
/// rollover hour, the same as for entries, so a photo taken at 1 AM goes with the evening before.
///
/// Photos can be fed in pieces. A day that carries on across two pieces stays one day.
struct PhotoDayGrouper {
    private(set) var days: [PhotoDay] = []
    private let calendar: DayCalendar
    private let gregorian: Calendar

    init(calendar: DayCalendar, timeZone: TimeZone) {
        self.calendar = calendar
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        gregorian = cal
    }

    var count: Int { days.last.map { $0.start + $0.count } ?? 0 }

    mutating func add(_ date: Date) {
        let stamp = calendar.stamp(for: date, using: gregorian)
        if let last = days.last, last.day == stamp {
            days[days.count - 1].count += 1
        } else {
            days.append(PhotoDay(day: stamp, start: count, count: 1))
        }
    }

    mutating func add(contentsOf dates: [Date]) {
        for date in dates { add(date) }
    }
}

enum PhotoDays {
    /// Where one day's photos are in a list sorted newest first, found by halving, so a library of any size is answered
    /// in a few looks at dates. Empty if there are none from that day. The range is where it would go.
    static func range(
        of day: DayStamp, count: Int, calendar: DayCalendar, timeZone: TimeZone, dateAt: (Int) -> Date
    ) -> Range<Int> {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        func stamp(_ index: Int) -> DayStamp { calendar.stamp(for: dateAt(index), using: gregorian) }

        // The first index whose day is not later than `day`, and then the first whose day is earlier.
        func firstIndex(where holds: (DayStamp) -> Bool) -> Int {
            var low = 0
            var high = count
            while low < high {
                let middle = (low + high) / 2
                if holds(stamp(middle)) { high = middle } else { low = middle + 1 }
            }
            return low
        }
        let start = firstIndex { $0 <= day }
        let end = firstIndex { $0 < day }
        return start..<end
    }
}
