import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class EntryFileTests: XCTestCase {
    let defaults = EntryFileDefaults(
        id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        journalID: Journal.defaultID,
        date: Date(timeIntervalSince1970: 0)
    )

    func roundTrip(_ entry: Entry) -> Entry {
        EntryFile.decode(EntryFile.encode(entry), defaults: defaults)
    }

    func testRoundTripKeepsEverything() {
        let entry = Entry(
            journalID: UUID(),
            createdAt: T.date("2026-10-17T21:14:03.250Z"),
            modifiedAt: T.date("2026-10-17T21:30:41Z"),
            timeZoneID: "UTC",
            templateID: UUID(),
            location: EntryLocation(name: "Café “Luna”, Portland", latitude: 45.52, longitude: -122.68),
            photos: [PhotoRef(fileName: "a.jpg", width: 2400, height: 1600), PhotoRef(fileName: "b.jpg", width: 900, height: 1200)],
            body: "## What went well?\n\nQuiet day. “Smart quotes”, emoji 🌙, and a \\ backslash.\n"
        )
        XCTAssertEqual(roundTrip(entry), entry)
    }

    /// A video is a photo, its still frame, with a link to the video in the Photos library.
    func testAVideoLinkSurvivesTheRoundTrip() {
        var entry = T.entry("2026-10-17T21:00:00Z", body: "![](photos/v.jpg)\n")
        let link = VideoLink(
            localID: "ABC-123/L0/001", cloudID: "cloud:xyz", duration: 72.4, takenAt: T.date("2026-10-17T19:02:11Z")
        )
        entry.photos = [
            PhotoRef(fileName: "a.jpg", width: 2400, height: 1600),
            PhotoRef(fileName: "v.jpg", width: 1920, height: 1080, video: link),
        ]
        let decoded = roundTrip(entry)
        XCTAssertEqual(decoded.photos, entry.photos)
        XCTAssertNil(decoded.photos[0].video)
        XCTAssertEqual(decoded.photos[1].video, link)
        // A plain photo is written as it always was, with no word of video.
        let text = String(decoding: EntryFile.encode(entry), as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "\"video\"").count - 1, 1)
    }

    /// A video added where the cloud name couldn't be had keeps what it has.
    func testAVideoLinkWithOnlyALocalNameIsRead() throws {
        let raw = #"[{"file":"v.jpg","h":1080,"id":"6F1D6A1E-3B0B-4B7C-9C59-0D0E4F1A2B3C","video":{"local":"L1","secs":5},"w":1920}]"#
        let photos = try JSONDecoder().decode([PhotoRef].self, from: Data(raw.utf8))
        XCTAssertEqual(photos.first?.video, VideoLink(localID: "L1", duration: 5))
    }

    func testVideoLengthIsWrittenLikeAClock() {
        XCTAssertEqual(VideoLink(localID: "x", duration: 0).durationText, "0:00")
        XCTAssertEqual(VideoLink(localID: "x", duration: 7.4).durationText, "0:07")
        XCTAssertEqual(VideoLink(localID: "x", duration: 59.6).durationText, "1:00")
        XCTAssertEqual(VideoLink(localID: "x", duration: 192).durationText, "3:12")
        XCTAssertEqual(VideoLink(localID: "x", duration: 3765).durationText, "1:02:45")
    }

    func testBodyThatLooksLikeAHeaderIsLeftAlone() {
        let body = "---\nid: \"not a real id\"\n---\n\nStill just text.\n---\n"
        var entry = T.entry("2026-10-17T21:00:00Z", body: body)
        entry.location = nil
        let decoded = roundTrip(entry)
        XCTAssertEqual(decoded.body, body)
        XCTAssertEqual(decoded.id, entry.id)
    }

    func testEmptyBodyAndBlankLeadingLines() {
        XCTAssertEqual(roundTrip(T.entry("2026-10-17T21:00:00Z", body: "")).body, "")
        XCTAssertEqual(roundTrip(T.entry("2026-10-17T21:00:00Z", body: "\n\nstarts blank")).body, "\n\nstarts blank")
    }

    func testBodyWithoutTrailingNewlineIsExact() {
        XCTAssertEqual(roundTrip(T.entry("2026-10-17T21:00:00Z", body: "no newline at end")).body, "no newline at end")
    }

    func testOptionalFieldsAreOmittedWhenEmpty() {
        let text = String(decoding: EntryFile.encode(T.entry("2026-10-17T21:00:00Z")), as: UTF8.self)
        XCTAssertFalse(text.contains("template:"))
        XCTAssertFalse(text.contains("location:"))
        XCTAssertFalse(text.contains("photos:"))
    }

    func testFileWithoutHeaderBecomesAnEntry() {
        let data = Data("Just a note I typed in Files.\nSecond line.".utf8)
        let entry = EntryFile.decode(data, defaults: defaults)
        XCTAssertEqual(entry.id, defaults.id)
        XCTAssertEqual(entry.journalID, Journal.defaultID)
        XCTAssertEqual(entry.createdAt, defaults.date)
        XCTAssertEqual(entry.body, "Just a note I typed in Files.\nSecond line.")
    }

    func testHandWrittenHeaderWithBareValues() {
        let text = "---\ncreated: 2026-10-17T21:00:00Z\ntimezone: UTC\n---\n\nHello\n"
        let entry = EntryFile.decode(Data(text.utf8), defaults: defaults)
        XCTAssertEqual(entry.createdAt, T.date("2026-10-17T21:00:00Z"))
        XCTAssertEqual(entry.timeZoneID, "UTC")
        XCTAssertEqual(entry.body, "Hello\n")
    }

    func testWindowsLineEndingsInHeader() {
        let text = "---\r\nid: \"22222222-2222-4222-8222-222222222222\"\r\ntimezone: \"UTC\"\r\n---\r\n\r\nBody"
        let entry = EntryFile.decode(Data(text.utf8), defaults: defaults)
        XCTAssertEqual(entry.id.uuidString, "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(entry.timeZoneID, "UTC")
    }

    func testBrokenOptionalFieldsDoNotLoseTheText() {
        let text = "---\nlocation: {not json\nphotos: [oops\n---\n\nImportant words\n"
        let entry = EntryFile.decode(Data(text.utf8), defaults: defaults)
        XCTAssertNil(entry.location)
        XCTAssertTrue(entry.photos.isEmpty)
        XCTAssertEqual(entry.body, "Important words\n")
    }

    func testHeaderIsHumanReadable() {
        let entry = T.entry("2026-10-17T21:14:03Z", body: "Hello")
        let text = String(decoding: EntryFile.encode(entry), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("---\nid: \""))
        XCTAssertTrue(text.contains("timezone: \"UTC\""))
        XCTAssertTrue(text.hasSuffix("---\n\nHello"))
    }
}
