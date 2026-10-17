import Foundation

struct OnThisDayGroup: Identifiable, Equatable {
    var year: Int
    var yearsAgo: Int
    /// Oldest first within the day.
    var entries: [Entry]

    var id: Int { year }

    var label: String {
        switch yearsAgo {
        case 1: return "1 year ago"
        default: return "\(yearsAgo) years ago"
        }
    }
}

enum OnThisDay {
    /// Entries written on today's month and day in earlier years, most recent year first.
    /// Feb 29 only matches other Feb 29 entries.
    static func groups(entries: [Entry], today: DayStamp, calendar: DayCalendar) -> [OnThisDayGroup] {
        var byYear: [Int: [Entry]] = [:]
        for entry in entries {
            let stamp = entry.dayStamp(using: calendar)
            guard stamp.month == today.month, stamp.day == today.day, stamp.year < today.year else { continue }
            byYear[stamp.year, default: []].append(entry)
        }
        return byYear
            .map { year, list in
                OnThisDayGroup(
                    year: year,
                    yearsAgo: today.year - year,
                    entries: list.sorted { $0.createdAt < $1.createdAt }
                )
            }
            .sorted { $0.year > $1.year }
    }
}
