import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

/// Loads a folder made by tools/make_sample_journal.py, to prove the Python writer and the Swift reader agree.
/// Skipped unless LAMPLIGHT_SAMPLE_DIR points at the folder that contains "Lamplight".
///
///     python3 tools/make_sample_journal.py /tmp/sample
///     LAMPLIGHT_SAMPLE_DIR=/tmp/sample swift test --filter SampleFolderTests
final class SampleFolderTests: XCTestCase {
    func testSampleFolderLoads() throws {
        guard let path = ProcessInfo.processInfo.environment["LAMPLIGHT_SAMPLE_DIR"] else {
            throw XCTSkip("Set LAMPLIGHT_SAMPLE_DIR to run this.")
        }
        let picked = URL(fileURLWithPath: path, isDirectory: true)
        let root = try LibraryLocator.resolveRoot(picked: picked, files: PlainFileAccess())
        XCTAssertEqual(root.lastPathComponent, "Lamplight")

        let library = Library(root: root)
        try library.prepare()

        XCTAssertEqual(library.loadJournals().map(\.name), ["Journal", "Dreams"])
        XCTAssertEqual(library.loadTemplates().map(\.name), ["Evening check-in", "Three good things"])
        XCTAssertEqual(library.loadSettings().home?.name, "Home")

        let result = library.loadAllEntries()
        XCTAssertTrue(result.failedIDs.isEmpty)
        XCTAssertGreaterThan(result.entries.count, 50)

        // Every photo an entry lists exists on disk and can be read.
        var photoCount = 0
        for entry in result.entries {
            for photo in entry.photos {
                let data = try library.readPhoto(entryID: entry.id, fileName: photo.fileName)
                XCTAssertGreaterThan(data.count, 1000)
                photoCount += 1
            }
        }
        XCTAssertGreaterThan(photoCount, 10)

        // Template entries are recognized, and summaries pick the answer as the title.
        let templated = result.entries.filter { $0.templateID != nil }
        XCTAssertFalse(templated.isEmpty)
        for entry in templated {
            XCTAssertFalse(entry.summary().title.hasPrefix("What"), entry.body)
        }

        // The sample is built around "now", so these hold whenever it is generated and tested.
        let calendar = DayCalendar()
        let now = Date()
        // The sample maker works out "today" on a fixed UTC-7 clock, with no daylight saving rules. Use the same clock
        // here. With the real Los Angeles zone, the hour after 07:00 UTC from November to March is still yesterday
        // there, and On This Day found nothing. That failed the Linux check once, at 07:26 UTC.
        let sampleClock = TimeZone(secondsFromGMT: -7 * 3600) ?? .current
        let stamp = calendar.stamp(for: now, timeZone: sampleClock)
        let streak = Streaks.summary(entries: result.entries, today: stamp, calendar: calendar)
        XCTAssertGreaterThanOrEqual(streak.longest, 12)
        let onThisDay = OnThisDay.groups(entries: result.entries, today: stamp, calendar: calendar)
        XCTAssertGreaterThanOrEqual(onThisDay.count, 3)
    }
}
