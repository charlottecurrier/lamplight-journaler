import XCTest
@testable import JournalCore

final class DayCalendarTests: XCTestCase {
    func testKnownDayNumbers() {
        XCTAssertEqual(DayMath.daysFromCivil(1970, 1, 1), 0)
        XCTAssertEqual(DayMath.daysFromCivil(2000, 3, 1), 11_017)
        XCTAssertEqual(DayMath.daysFromCivil(2024, 2, 29), 19_782)
    }

    func testDayNumberRoundTrip() {
        for n in stride(from: -800, through: 30_000, by: 37) {
            let stamp = DayStamp(dayNumber: n)
            XCTAssertEqual(stamp.dayNumber, n)
        }
    }

    func testAddingDaysCrossesMonthAndLeapDay() {
        XCTAssertEqual(DayStamp(year: 2024, month: 2, day: 28).adding(days: 1), DayStamp(year: 2024, month: 2, day: 29))
        XCTAssertEqual(DayStamp(year: 2023, month: 2, day: 28).adding(days: 1), DayStamp(year: 2023, month: 3, day: 1))
        XCTAssertEqual(DayStamp(year: 2026, month: 1, day: 1).adding(days: -1), DayStamp(year: 2025, month: 12, day: 31))
    }

    func testStampUsesTheGivenTimeZone() {
        // 03:30 UTC on Oct 18 is still Oct 17 at UTC-5.
        let date = T.date("2026-10-18T03:30:00Z")
        let utc = DayCalendar().stamp(for: date, timeZone: TimeZone(identifier: "UTC")!)
        let minus5 = DayCalendar().stamp(for: date, timeZone: TimeZone(secondsFromGMT: -5 * 3600)!)
        XCTAssertEqual(utc, DayStamp(year: 2026, month: 10, day: 18))
        XCTAssertEqual(minus5, DayStamp(year: 2026, month: 10, day: 17))
    }

    func testRolloverKeepsLateNightWritingWithTheDayBefore() {
        let late = T.date("2026-10-18T00:40:00Z")
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(DayCalendar(rolloverHour: 0).stamp(for: late, timeZone: utc), DayStamp(year: 2026, month: 10, day: 18))
        XCTAssertEqual(DayCalendar(rolloverHour: 3).stamp(for: late, timeZone: utc), DayStamp(year: 2026, month: 10, day: 17))
        // 3:30 AM is after a 3 AM rollover, so it belongs to the new day.
        let after = T.date("2026-10-18T03:30:00Z")
        XCTAssertEqual(DayCalendar(rolloverHour: 3).stamp(for: after, timeZone: utc), DayStamp(year: 2026, month: 10, day: 18))
    }
}

final class StreakTests: XCTestCase {
    let today = DayStamp(year: 2026, month: 10, day: 17)
    let calendar = DayCalendar()

    func entries(_ days: [String]) -> [Entry] {
        days.map { T.entry("\($0)T21:00:00Z") }
    }

    func testNoEntries() {
        XCTAssertEqual(Streaks.summary(entries: [], today: today, calendar: calendar), .empty)
    }

    func testStreakIncludingToday() {
        let s = Streaks.summary(
            entries: entries(["2026-10-15", "2026-10-16", "2026-10-17"]),
            today: today, calendar: calendar
        )
        XCTAssertEqual(s.current, 3)
        XCTAssertTrue(s.wroteToday)
        XCTAssertFalse(s.needsTodayToContinue)
        XCTAssertEqual(s.lastSevenDays, [false, false, false, false, true, true, true])
    }

    func testStreakStaysAliveThroughYesterday() {
        let s = Streaks.summary(
            entries: entries(["2026-10-14", "2026-10-15", "2026-10-16"]),
            today: today, calendar: calendar
        )
        XCTAssertEqual(s.current, 3)
        XCTAssertFalse(s.wroteToday)
        XCTAssertTrue(s.needsTodayToContinue)
    }

    func testStreakBreaksAfterAMissedDay() {
        let s = Streaks.summary(
            entries: entries(["2026-10-13", "2026-10-14", "2026-10-15"]),
            today: today, calendar: calendar
        )
        XCTAssertEqual(s.current, 0)
        XCTAssertEqual(s.longest, 3)
    }

    func testTwoEntriesOnOneDayCountOnce() {
        let list = entries(["2026-10-16", "2026-10-16", "2026-10-17"])
        let s = Streaks.summary(entries: list, today: today, calendar: calendar)
        XCTAssertEqual(s.current, 2)
        XCTAssertEqual(s.totalDays, 2)
        XCTAssertEqual(s.totalEntries, 3)
    }

    func testLongestIsFoundInThePast() {
        let s = Streaks.summary(
            entries: entries([
                "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05",
                "2026-10-16", "2026-10-17",
            ]),
            today: today, calendar: calendar
        )
        XCTAssertEqual(s.current, 2)
        XCTAssertEqual(s.longest, 5)
    }

    func testStreakAcrossMonthAndYearBoundary() {
        let s = Streaks.summary(
            entries: entries(["2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02"]),
            today: DayStamp(year: 2026, month: 1, day: 2), calendar: calendar
        )
        XCTAssertEqual(s.current, 4)
    }

    func testPastMidnightEntryKeepsTheStreakWithRollover() {
        // Writes at 12:30 AM on the 17th, meaning the night of the 16th.
        let list = [
            T.entry("2026-10-15T22:00:00Z"),
            T.entry("2026-10-17T00:30:00Z"),
        ]
        let withoutRollover = Streaks.summary(entries: list, today: DayStamp(year: 2026, month: 10, day: 17), calendar: DayCalendar(rolloverHour: 0))
        let withRollover = Streaks.summary(entries: list, today: DayStamp(year: 2026, month: 10, day: 16), calendar: DayCalendar(rolloverHour: 3))
        XCTAssertEqual(withoutRollover.current, 1)
        XCTAssertEqual(withRollover.current, 2)
    }
}

final class OnThisDayTests: XCTestCase {
    let calendar = DayCalendar()

    func testGroupsByYearMostRecentFirst() {
        let list = [
            T.entry("2025-10-17T20:00:00Z", body: "last year"),
            T.entry("2023-10-17T09:00:00Z", body: "three years, morning"),
            T.entry("2023-10-17T21:00:00Z", body: "three years, evening"),
            T.entry("2025-10-16T20:00:00Z", body: "wrong day"),
            T.entry("2026-10-17T08:00:00Z", body: "today"),
        ]
        let groups = OnThisDay.groups(entries: list, today: DayStamp(year: 2026, month: 10, day: 17), calendar: calendar)
        XCTAssertEqual(groups.map(\.year), [2025, 2023])
        XCTAssertEqual(groups.map(\.yearsAgo), [1, 3])
        XCTAssertEqual(groups[0].label, "1 year ago")
        XCTAssertEqual(groups[1].label, "3 years ago")
        XCTAssertEqual(groups[1].entries.map(\.body), ["three years, morning", "three years, evening"])
    }

    func testNothingWhenNoEarlierYears() {
        let list = [T.entry("2026-10-17T08:00:00Z")]
        XCTAssertTrue(OnThisDay.groups(entries: list, today: DayStamp(year: 2026, month: 10, day: 17), calendar: calendar).isEmpty)
    }

    func testLeapDayOnlyMatchesLeapDays() {
        let list = [
            T.entry("2024-02-29T10:00:00Z"),
            T.entry("2023-02-28T10:00:00Z"),
        ]
        let groups = OnThisDay.groups(entries: list, today: DayStamp(year: 2028, month: 2, day: 29), calendar: calendar)
        XCTAssertEqual(groups.map(\.year), [2024])
    }
}
