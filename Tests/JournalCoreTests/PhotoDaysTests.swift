import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class PhotoDaysTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date { T.date(iso) }

    private func group(_ isos: [String], rollover: Int = 0, zone: TimeZone? = nil) -> [PhotoDay] {
        var grouper = PhotoDayGrouper(calendar: DayCalendar(rolloverHour: rollover), timeZone: zone ?? utc)
        grouper.add(contentsOf: isos.map(date))
        return grouper.days
    }

    func testPhotosFromOneDayShareASection() {
        let days = group(["2026-10-17T22:00:00Z", "2026-10-17T09:00:00Z", "2026-10-16T23:59:00Z", "2026-10-15T08:00:00Z"])
        XCTAssertEqual(days, [
            PhotoDay(day: DayStamp(year: 2026, month: 10, day: 17), start: 0, count: 2),
            PhotoDay(day: DayStamp(year: 2026, month: 10, day: 16), start: 2, count: 1),
            PhotoDay(day: DayStamp(year: 2026, month: 10, day: 15), start: 3, count: 1),
        ])
        XCTAssertEqual(days[0].range, 0..<2)
    }

    func testNoPhotosMakesNoDays() {
        XCTAssertEqual(group([]), [])
    }

    func testTheRolloverHourKeepsAnEarlyMorningPhotoWithTheEveningBefore() {
        // 1:30 AM on the 17th is still the 16th when the day starts at 4 AM.
        let days = group(["2026-10-17T05:00:00Z", "2026-10-17T01:30:00Z", "2026-10-16T20:00:00Z"], rollover: 4)
        XCTAssertEqual(days.map(\.day), [DayStamp(year: 2026, month: 10, day: 17), DayStamp(year: 2026, month: 10, day: 16)])
        XCTAssertEqual(days.map(\.count), [1, 2])
    }

    func testTheTimeZoneDecidesWhereADayEnds() {
        // The same moment is the 17th in Tokyo and the 16th in New York.
        let moment = ["2026-10-17T02:00:00Z"]
        XCTAssertEqual(group(moment, zone: TimeZone(identifier: "Asia/Tokyo")!).first?.day, DayStamp(year: 2026, month: 10, day: 17))
        XCTAssertEqual(group(moment, zone: TimeZone(identifier: "America/New_York")!).first?.day, DayStamp(year: 2026, month: 10, day: 16))
    }

    func testADayThatCarriesOnAcrossPiecesStaysOneDay() {
        var grouper = PhotoDayGrouper(calendar: DayCalendar(), timeZone: utc)
        grouper.add(contentsOf: ["2026-10-17T22:00:00Z", "2026-10-17T20:00:00Z"].map(date))
        grouper.add(contentsOf: ["2026-10-17T10:00:00Z", "2026-10-16T10:00:00Z"].map(date))
        XCTAssertEqual(grouper.days.map(\.count), [3, 1])
        XCTAssertEqual(grouper.days.map(\.start), [0, 3])
        XCTAssertEqual(grouper.count, 4)
    }

    // MARK: Finding one day

    private func range(of day: DayStamp, in isos: [String], rollover: Int = 0) -> Range<Int> {
        let dates = isos.map(date)
        return PhotoDays.range(of: day, count: dates.count, calendar: DayCalendar(rolloverHour: rollover), timeZone: utc) { dates[$0] }
    }

    func testFindsTheRunOfADay() {
        let isos = [
            "2026-10-20T10:00:00Z", "2026-10-18T23:00:00Z", "2026-10-18T09:00:00Z", "2026-10-18T00:30:00Z",
            "2026-10-17T12:00:00Z", "2026-10-12T12:00:00Z",
        ]
        XCTAssertEqual(range(of: DayStamp(year: 2026, month: 10, day: 18), in: isos), 1..<4)
        XCTAssertEqual(range(of: DayStamp(year: 2026, month: 10, day: 20), in: isos), 0..<1)
        XCTAssertEqual(range(of: DayStamp(year: 2026, month: 10, day: 12), in: isos), 5..<6)
    }

    func testADayWithNoPhotosGivesAnEmptyRange() {
        let isos = ["2026-10-20T10:00:00Z", "2026-10-18T09:00:00Z", "2026-10-12T12:00:00Z"]
        for day in [DayStamp(year: 2026, month: 10, day: 19), DayStamp(year: 2026, month: 11, day: 1), DayStamp(year: 2020, month: 1, day: 1)] {
            XCTAssertTrue(range(of: day, in: isos).isEmpty, "\(day)")
        }
        XCTAssertTrue(range(of: DayStamp(year: 2026, month: 10, day: 1), in: []).isEmpty)
    }

    /// Halving has to agree with counting, for any library: photos at random moments, with and without a rollover.
    func testFindingAgreesWithCountingOnRandomLibraries() {
        var generator = SystemRandomNumberGenerator()
        for rollover in [0, 4] {
            let calendar = DayCalendar(rolloverHour: rollover)
            for _ in 0..<40 {
                let size = Int.random(in: 0...120, using: &generator)
                let base = date("2026-01-01T00:00:00Z")
                let dates = (0..<size)
                    .map { _ in base.addingTimeInterval(Double(Int.random(in: 0...(20 * 86_400), using: &generator))) }
                    .sorted(by: >)
                var grouper = PhotoDayGrouper(calendar: calendar, timeZone: utc)
                grouper.add(contentsOf: dates)
                for day in (0..<22).map({ DayStamp(year: 2026, month: 1, day: 1).adding(days: $0) }) {
                    let found = PhotoDays.range(of: day, count: dates.count, calendar: calendar, timeZone: utc) { dates[$0] }
                    let counted = grouper.days.first { $0.day == day }?.range
                    if let counted {
                        XCTAssertEqual(found, counted, "day \(day), rollover \(rollover)")
                    } else {
                        XCTAssertTrue(found.isEmpty, "day \(day), rollover \(rollover)")
                    }
                }
            }
        }
    }
}
