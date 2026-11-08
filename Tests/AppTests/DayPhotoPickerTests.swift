import Photos
import XCTest
@testable import Lamplight

/// A list of photos with known dates, in place of the Photos library. The picker reads its photos through
/// `PhotoListing`, so how it lays out the days is checked here on every run, with no library and no permission.
/// `PhotoLibraryTests` checks the same against the real library when the app is allowed to read it.
struct FakeListing: PhotoListing {
    private let photos: [(id: String, taken: Date)]

    /// Photos by name, each with the moment it was taken. They are listed newest first, as the library lists them.
    init(_ taken: [String: Date]) {
        photos = taken.map { (id: $0.key, taken: $0.value) }.sorted { $0.taken > $1.taken }
    }

    var count: Int { photos.count }
    func date(at index: Int) -> Date? { photos[index].taken }
    func identifier(at index: Int) -> String { photos[index].id }
    func asset(at index: Int) -> PHAsset? { nil }
}

@MainActor
final class DayPhotoPickerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date { T.date(iso) }

    /// A picker for an entry written at a moment, over a fake library, finished loading.
    private func loadedModel(
        _ photos: [String: Date], entryAt entry: String, rollover: Int = 0
    ) async -> DayPhotoPickerModel {
        let listing = FakeListing(photos)
        let model = DayPhotoPickerModel(
            entryDate: date(entry), timeZone: utc, calendar: DayCalendar(rolloverHour: rollover),
            accessNow: { .full }, makeListing: { listing }
        )
        await model.load()
        return model
    }

    private func identifiers(_ day: PickerDay, in model: DayPhotoPickerModel) -> [String] {
        (0..<day.count).compactMap { model.identifier(in: day, at: $0) }
    }

    // MARK: Days

    func testTheDayOfTheEntryComesFirstThenOtherDaysNewestFirst() async throws {
        let model = await loadedModel([
            "early": date("2012-03-10T09:00:00Z"), "late": date("2012-03-10T21:30:00Z"),
            "before": date("2012-03-05T10:00:00Z"), "after": date("2012-03-12T08:00:00Z"),
            "newest": date("2012-03-14T12:00:00Z"),
        ], entryAt: "2012-03-10T12:00:00Z")

        let entryDay = try XCTUnwrap(model.days.first)
        XCTAssertTrue(entryDay.isEntryDay)
        XCTAssertEqual(entryDay.day, DayStamp(year: 2012, month: 3, day: 10))
        XCTAssertEqual(identifiers(entryDay, in: model), ["early", "late"], "The day's photos run oldest first.")

        // The other days follow newest first, and the entry's day is not listed twice.
        let others = Array(model.days.dropFirst())
        XCTAssertTrue(others.allSatisfy { !$0.isEntryDay })
        XCTAssertEqual(others.map(\.day), [
            DayStamp(year: 2012, month: 3, day: 14), DayStamp(year: 2012, month: 3, day: 12), DayStamp(year: 2012, month: 3, day: 5),
        ])
        XCTAssertEqual(others.map { identifiers($0, in: model) }, [["newest"], ["after"], ["before"]])
    }

    func testADayWithNoPhotosIsStillListedFirst() async throws {
        let model = await loadedModel(["other": date("2011-01-05T12:00:00Z")], entryAt: "2011-01-01T12:00:00Z")
        let first = try XCTUnwrap(model.days.first)
        XCTAssertTrue(first.isEntryDay)
        XCTAssertEqual(first.count, 0)
        XCTAssertEqual(model.days.map(\.day), [DayStamp(year: 2011, month: 1, day: 1), DayStamp(year: 2011, month: 1, day: 5)])
    }

    func testAnEmptyLibraryListsOnlyTheDayOfTheEntry() async throws {
        let model = await loadedModel([:], entryAt: "2011-01-01T12:00:00Z")
        XCTAssertEqual(model.days.count, 1)
        XCTAssertEqual(model.days.first?.count, 0)
        XCTAssertFalse(model.isLoading)
    }

    func testTheRolloverHourKeepsAnEarlyMorningPhotoWithTheDayBefore() async throws {
        // 1:30 AM on the 21st belongs to the 20th when the day starts at 4 AM.
        let model = await loadedModel([
            "evening": date("2013-05-20T20:00:00Z"), "small": date("2013-05-21T01:30:00Z"),
            "morning": date("2013-05-21T09:00:00Z"),
        ], entryAt: "2013-05-20T22:00:00Z", rollover: 4)
        let entryDay = try XCTUnwrap(model.days.first)
        XCTAssertEqual(identifiers(entryDay, in: model), ["evening", "small"])
        XCTAssertEqual(model.days.dropFirst().map { identifiers($0, in: model) }, [["morning"]])
    }

    /// The library is read in pieces of 1500 photos. Days that run across the edge of a piece must still come out whole.
    func testABigLibraryIsLaidOutWholeAcrossTheReadsInPieces() async throws {
        var photos: [String: Date] = [:]
        let start = date("2020-01-01T00:00:00Z")
        for number in 0..<4000 {
            // 100 photos a day for 40 days, a minute apart.
            let day = number / 100
            photos["photo-\(number)"] = start.addingTimeInterval(Double(day) * 86_400 + Double(number % 100) * 60)
        }
        let model = await loadedModel(photos, entryAt: "2020-01-20T12:00:00Z")
        XCTAssertEqual(model.days.count, 40)
        XCTAssertEqual(model.days.map(\.count).reduce(0, +), 4000)
        XCTAssertTrue(model.days.allSatisfy { $0.count == 100 })
        XCTAssertEqual(model.days.first?.day, DayStamp(year: 2020, month: 1, day: 20))
        XCTAssertEqual(model.days.filter { $0.day == DayStamp(year: 2020, month: 1, day: 20) }.count, 1)
        let entryDay = try XCTUnwrap(model.days.first)
        let ids = identifiers(entryDay, in: model)
        XCTAssertEqual(ids.first, "photo-1900")
        XCTAssertEqual(ids.last, "photo-1999")
    }

    func testNothingIsReadWithoutAccess() async throws {
        var read = false
        let model = DayPhotoPickerModel(
            entryDate: date("2012-03-10T12:00:00Z"), timeZone: utc, calendar: DayCalendar(),
            accessNow: { .denied }, makeListing: { read = true; return FakeListing([:]) }
        )
        await model.load()
        XCTAssertFalse(read, "The library was read without access to it.")
        XCTAssertTrue(model.days.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    // MARK: Choosing

    func testChoosingKeepsTheOrderTappedAndStopsAtTheLimit() {
        let model = DayPhotoPickerModel(
            entryDate: Date(), timeZone: utc, calendar: DayCalendar(), accessNow: { .full }, makeListing: { FakeListing([:]) }
        )
        for number in 1...(DayPhotoPickerModel.limit + 3) { model.toggle("photo-\(number)") }
        XCTAssertEqual(model.selected.count, DayPhotoPickerModel.limit)
        XCTAssertEqual(model.selected.first, "photo-1")
        XCTAssertEqual(model.number(of: "photo-3"), 3)
        XCTAssertNil(model.number(of: "photo-\(DayPhotoPickerModel.limit + 1)"))
        XCTAssertTrue(model.isFull)

        model.toggle("photo-2")
        XCTAssertEqual(model.number(of: "photo-3"), 2, "Numbers close up when one is taken out.")
        XCTAssertFalse(model.isFull)
    }
}
