import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class MoonPhaseTests: XCTestCase {
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Distance between two ages on the circle of the cycle.
    private func apart(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, MoonPhase.cycleDays - d)
    }

    func testTheReferenceNewMoonIsAgeZero() {
        XCTAssertEqual(MoonPhase(on: utc(2000, 1, 6, 18, 14)).age, 0, accuracy: 0.001)
    }

    func testKnownMoonsAreCloseToTheirPhase() {
        // Full moon 25 Jan 2024 17:54 UTC, new moon 9 Feb 2024 22:59 UTC, quarters 2 Feb and 16 Feb 2024.
        let half = MoonPhase.cycleDays / 2
        XCTAssertLessThan(apart(MoonPhase(on: utc(2024, 1, 25, 17, 54)).age, half), 0.75)
        XCTAssertLessThan(apart(MoonPhase(on: utc(2024, 2, 9, 22, 59)).age, 0), 0.75)
        XCTAssertLessThan(apart(MoonPhase(on: utc(2024, 2, 16, 15, 1)).age, half / 2), 0.75)
        XCTAssertLessThan(apart(MoonPhase(on: utc(2024, 2, 2, 23, 18)).age, half * 1.5), 0.75)
    }

    func testDatesBeforeTheReferenceStillWrapIntoOneCycle() {
        for year in [1969, 1985, 1999] {
            let age = MoonPhase(on: utc(year, 6, 15)).age
            XCTAssertGreaterThanOrEqual(age, 0)
            XCTAssertLessThan(age, MoonPhase.cycleDays)
        }
    }

    func testNamesAcrossACycle() {
        XCTAssertEqual(MoonPhase(age: 0).name, "New moon")
        XCTAssertEqual(MoonPhase(age: 3.5).name, "Waxing crescent")
        XCTAssertEqual(MoonPhase(age: 7.4).name, "First quarter")
        XCTAssertEqual(MoonPhase(age: 11).name, "Waxing gibbous")
        XCTAssertEqual(MoonPhase(age: 14.77).name, "Full moon")
        XCTAssertEqual(MoonPhase(age: 18).name, "Waning gibbous")
        XCTAssertEqual(MoonPhase(age: 22.1).name, "Last quarter")
        XCTAssertEqual(MoonPhase(age: 26).name, "Waning crescent")
        XCTAssertEqual(MoonPhase(age: 29.4).name, "New moon")
    }

    func testIlluminationAndShape() {
        XCTAssertEqual(MoonPhase(age: 0).illumination, 0, accuracy: 0.001)
        XCTAssertEqual(MoonPhase(age: MoonPhase.cycleDays / 4).illumination, 0.5, accuracy: 0.001)
        XCTAssertEqual(MoonPhase(age: MoonPhase.cycleDays / 2).illumination, 1, accuracy: 0.001)
        XCTAssertEqual(MoonPhase(age: 0).terminator, 1, accuracy: 0.001)
        XCTAssertEqual(MoonPhase(age: MoonPhase.cycleDays / 4).terminator, 0, accuracy: 0.001)
        XCTAssertEqual(MoonPhase(age: MoonPhase.cycleDays / 2).terminator, -1, accuracy: 0.001)
    }

    func testWaxingIsTheFirstHalfOfTheCycle() {
        XCTAssertTrue(MoonPhase(age: 5).isWaxing)
        XCTAssertFalse(MoonPhase(age: 20).isWaxing)
    }
}
