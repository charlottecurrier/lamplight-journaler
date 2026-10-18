import Foundation

struct StreakSummary: Equatable {
    /// Days in a row ending today. If nothing is written yet today, the streak still counts through yesterday.
    var current: Int
    var longest: Int
    var totalDays: Int
    var totalEntries: Int
    var wroteToday: Bool
    /// Oldest first, the last item is today.
    var lastSevenDays: [Bool]

    /// True when there is a streak to keep and today is still open.
    var needsTodayToContinue: Bool { current > 0 && !wroteToday }

    static let empty = StreakSummary(
        current: 0, longest: 0, totalDays: 0, totalEntries: 0,
        wroteToday: false, lastSevenDays: Array(repeating: false, count: 7)
    )
}

enum Streaks {
    static func summary(entries: [Entry], today: DayStamp, calendar: DayCalendar) -> StreakSummary {
        let days = Set(entries.map { $0.dayStamp(using: calendar).dayNumber })
        return summary(days: days, entryCount: entries.count, today: today)
    }

    static func summary(days: Set<Int>, entryCount: Int, today: DayStamp) -> StreakSummary {
        guard !days.isEmpty else { return .empty }

        let todayNumber = today.dayNumber
        let wroteToday = days.contains(todayNumber)

        var current = 0
        var cursor = wroteToday ? todayNumber : todayNumber - 1
        while days.contains(cursor) {
            current += 1
            cursor -= 1
        }

        var longest = 0
        var run = 0
        var previous: Int?
        for day in days.sorted() {
            if let p = previous, day == p + 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        let lastSeven = (0..<7).reversed().map { days.contains(todayNumber - $0) }

        return StreakSummary(
            current: current,
            longest: longest,
            totalDays: days.count,
            totalEntries: entryCount,
            wroteToday: wroteToday,
            lastSevenDays: lastSeven
        )
    }
}

extension StreakSummary {
    /// The line shown after the first entry of a day is saved. Calm, not cheerleading.
    var savedMessage: String {
        switch current {
        case 0, 1: return "Saved. Day one."
        case 7: return "Saved. A full week."
        case 14: return "Saved. Two weeks."
        case 30: return "Saved. Thirty days in a row."
        case 100: return "Saved. One hundred days."
        case 365: return "Saved. A whole year."
        default: return "Saved. \(current) days in a row."
        }
    }
}
