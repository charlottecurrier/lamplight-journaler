import Photos
import UIKit
import XCTest
@testable import Lamplight

/// The photo picker against a real Photos library: it puts photos with known dates into the simulator's library
/// and checks how the picker lists them. They need access to Photos, which the Mac job grants to the app before the
/// tests run. Without access they are skipped.
@MainActor
final class DayPhotoPickerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date { T.date(iso) }

    /// Skips when the app can't read Photos, unless the run says it must: the Mac job sets REQUIRE_PHOTOS, because a
    /// skipped test looks like a passing one and these are the tests that look in a real library.
    private func requireAccess() throws {
        guard PhotoAccess.current == .full else {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue
            let adding = PHPhotoLibrary.authorizationStatus(for: .addOnly).rawValue
            let note = "Photos access isn't granted to \(Bundle.main.bundleIdentifier ?? "the app") (read and write "
                + "status \(status), add only status \(adding)), so there is no library to look in."
            if ProcessInfo.processInfo.environment["REQUIRE_PHOTOS"] == "1" {
                XCTFail(note)
            }
            throw XCTSkip(note)
        }
    }

    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
    }

    /// Adds a photo to the library as if it had been taken at a moment, and returns its identifier.
    private func addPhoto(taken moment: Date, color: UIColor = .gray) async throws -> String {
        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: self.image(color))
            request.creationDate = moment
            identifier = request.placeholderForCreatedAsset?.localIdentifier
        }
        return try XCTUnwrap(identifier, "The new photo has no identifier.")
    }

    /// A picker for an entry written at a moment, finished loading.
    private func loadedModel(entryAt entry: String, rollover: Int = 0) async -> DayPhotoPickerModel {
        let model = DayPhotoPickerModel(entryDate: date(entry), timeZone: utc, calendar: DayCalendar(rolloverHour: rollover))
        await model.load()
        return model
    }

    private func identifiers(_ day: PickerDay, in model: DayPhotoPickerModel) -> [String] {
        (0..<day.count).compactMap { model.asset(in: day, at: $0)?.localIdentifier }
    }

    // MARK: Days

    func testTheDayOfTheEntryComesFirstThenOtherDaysNewestFirst() async throws {
        try requireAccess()
        // Years back, so nothing else in the library is near them.
        let early = try await addPhoto(taken: date("2012-03-10T09:00:00Z"))
        let late = try await addPhoto(taken: date("2012-03-10T21:30:00Z"))
        let before = try await addPhoto(taken: date("2012-03-05T10:00:00Z"))
        let after = try await addPhoto(taken: date("2012-03-12T08:00:00Z"))
        let newest = try await addPhoto(taken: date("2012-03-14T12:00:00Z"))

        let model = await loadedModel(entryAt: "2012-03-10T12:00:00Z")
        XCTAssertEqual(model.days.first?.isEntryDay, true)
        XCTAssertEqual(model.days.first?.day, DayStamp(year: 2012, month: 3, day: 10))
        let entryDay = try XCTUnwrap(model.days.first)
        XCTAssertEqual(identifiers(entryDay, in: model), [early, late], "The day's photos run oldest first.")

        // The other days follow newest first, and the entry's day is not listed twice.
        let others = model.days.dropFirst()
        XCTAssertFalse(others.contains { $0.day == entryDay.day })
        XCTAssertTrue(others.allSatisfy { !$0.isEntryDay })
        let ours = others.filter { [newest, after, before].contains(identifiers($0, in: model).first ?? "") }
        XCTAssertEqual(ours.map(\.day), [
            DayStamp(year: 2012, month: 3, day: 14), DayStamp(year: 2012, month: 3, day: 12), DayStamp(year: 2012, month: 3, day: 5),
        ])
    }

    func testADayWithNoPhotosIsStillListedFirst() async throws {
        try requireAccess()
        let model = await loadedModel(entryAt: "2011-01-01T12:00:00Z")
        let first = try XCTUnwrap(model.days.first)
        XCTAssertTrue(first.isEntryDay)
        XCTAssertEqual(first.count, 0)
    }

    func testTheRolloverHourKeepsAnEarlyMorningPhotoWithTheDayBefore() async throws {
        try requireAccess()
        // 1:30 AM on the 21st belongs to the 20th when the day starts at 4 AM.
        let evening = try await addPhoto(taken: date("2013-05-20T20:00:00Z"))
        let small = try await addPhoto(taken: date("2013-05-21T01:30:00Z"))
        let model = await loadedModel(entryAt: "2013-05-20T22:00:00Z", rollover: 4)
        let entryDay = try XCTUnwrap(model.days.first)
        XCTAssertEqual(identifiers(entryDay, in: model), [evening, small])
    }

    // MARK: Choosing

    func testChoosingKeepsTheOrderTappedAndStopsAtTheLimit() {
        let model = DayPhotoPickerModel(entryDate: Date(), timeZone: utc, calendar: DayCalendar(), access: .full)
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

    // MARK: Pictures

    func testChosenPhotosComeBackAsPicturesTheJournalCanKeep() async throws {
        try requireAccess()
        let first = try await addPhoto(taken: date("2014-02-01T10:00:00Z"), color: .red)
        let second = try await addPhoto(taken: date("2014-02-01T11:00:00Z"), color: .green)
        let data = await DayPhotoPickerModel.imageData(for: [second, first])
        XCTAssertEqual(data.count, 2)
        for item in data {
            XCTAssertNotNil(ImageTools.prepareForStorage(item), "The photo's data can't be read as a picture.")
        }
    }

    func testAThumbnailArrives() async throws {
        try requireAccess()
        _ = try await addPhoto(taken: date("2015-07-04T10:00:00Z"))
        let model = await loadedModel(entryAt: "2015-07-04T12:00:00Z")
        let day = try XCTUnwrap(model.days.first)
        let asset = try XCTUnwrap(model.asset(in: day, at: 0))
        var received: UIImage?
        for await next in model.thumbnails(for: asset, side: 120) {
            received = next
            break
        }
        XCTAssertNotNil(received)
    }
}
