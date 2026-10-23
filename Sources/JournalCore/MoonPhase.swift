import Foundation

/// Where the moon is in its cycle. It uses the average length of the cycle, so it can be off by about half a day
/// near the turning points. That is close enough for a small moon drawn beside an entry.
struct MoonPhase: Equatable {
    static let cycleDays = 29.530588853

    /// A new moon: 6 January 2000, 18:14 UTC.
    private static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    /// Days since the last new moon, from 0 up to the length of the cycle.
    let age: Double

    init(on date: Date) {
        let days = date.timeIntervalSince(Self.referenceNewMoon) / 86_400
        var wrapped = days.truncatingRemainder(dividingBy: Self.cycleDays)
        if wrapped < 0 { wrapped += Self.cycleDays }
        self.age = wrapped
    }

    init(age: Double) {
        self.age = age
    }

    private var cycleFraction: Double { age / Self.cycleDays }

    /// True from the new moon to the full moon, when the right side is the lit side.
    var isWaxing: Bool { cycleFraction < 0.5 }

    /// 0 at a new moon and 1 at a full moon.
    var illumination: Double { (1 - cos(2 * .pi * cycleFraction)) / 2 }

    /// Where the edge between light and dark sits across the disc: 1 at a new moon, 0 at the quarters,
    /// -1 at a full moon.
    var terminator: Double { cos(2 * .pi * cycleFraction) }

    var name: String {
        // The new, quarter and full moons each cover a day either side of their moment.
        let day = 1 / Self.cycleDays
        let f = cycleFraction
        switch f {
        case ..<day: return "New moon"
        case ..<(0.25 - day): return "Waxing crescent"
        case ..<(0.25 + day): return "First quarter"
        case ..<(0.5 - day): return "Waxing gibbous"
        case ..<(0.5 + day): return "Full moon"
        case ..<(0.75 - day): return "Waning gibbous"
        case ..<(0.75 + day): return "Last quarter"
        case ..<(1 - day): return "Waning crescent"
        default: return "New moon"
        }
    }
}
