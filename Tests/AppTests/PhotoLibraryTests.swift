import Photos
import UIKit
import XCTest
@testable import Lamplight

/// The picker against the real Photos library: these put photos with known dates into the simulator's library and read
/// them back, which checks what the fake listing in `DayPhotoPickerTests` can't: that the library lists photos newest
/// first, that places in a day line up with photos, that a chosen photo comes back as a picture, and that a thumbnail
/// arrives.
///
/// They need the app to be allowed to read Photos, and they skip without it. **They skip in the Mac job on GitHub.** The
/// simulator there shows the permission as granted in its privacy database, but the test app still reads "not decided"
/// from it, and nothing can tap the system's prompt. To run them in Xcode, run the app once in the iPad simulator, open
/// the photo picker from an entry, and choose Allow Access to All Photos. They add a few photos dated years back to that
/// simulator's library and leave them there.
@MainActor
final class PhotoLibraryTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date { T.date(iso) }

    private func requireAccess() throws {
        guard PhotoAccess.current == .full else {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue
            throw XCTSkip("Photos access isn't granted to the app (status \(status)), so there is no library to look in.")
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

    private func loadedModel(entryAt entry: String) async -> DayPhotoPickerModel {
        let model = DayPhotoPickerModel(entryDate: date(entry), timeZone: utc, calendar: DayCalendar(rolloverHour: 0))
        await model.load()
        return model
    }

    private func identifiers(_ day: PickerDay, in model: DayPhotoPickerModel) -> [String] {
        (0..<day.count).compactMap { model.identifier(in: day, at: $0) }
    }

    func testTheLibraryListsTheDayOfTheEntryFirstThenOtherDaysNewestFirst() async throws {
        try requireAccess()
        // Years back, so nothing else in the library is near them.
        let early = try await addPhoto(taken: date("2012-03-10T09:00:00Z"))
        let late = try await addPhoto(taken: date("2012-03-10T21:30:00Z"))
        let before = try await addPhoto(taken: date("2012-03-05T10:00:00Z"))
        let after = try await addPhoto(taken: date("2012-03-12T08:00:00Z"))
        let newest = try await addPhoto(taken: date("2012-03-14T12:00:00Z"))

        let model = await loadedModel(entryAt: "2012-03-10T12:00:00Z")
        let entryDay = try XCTUnwrap(model.days.first)
        XCTAssertTrue(entryDay.isEntryDay)
        XCTAssertEqual(entryDay.day, DayStamp(year: 2012, month: 3, day: 10))
        XCTAssertEqual(identifiers(entryDay, in: model), [early, late], "The day's photos run oldest first.")

        let others = model.days.dropFirst()
        XCTAssertFalse(others.contains { $0.day == entryDay.day })
        let ours = others.filter { [newest, after, before].contains(identifiers($0, in: model).first ?? "") }
        XCTAssertEqual(ours.map(\.day), [
            DayStamp(year: 2012, month: 3, day: 14), DayStamp(year: 2012, month: 3, day: 12), DayStamp(year: 2012, month: 3, day: 5),
        ])
        XCTAssertNotNil(model.asset(in: entryDay, at: 0), "The grid needs the library's record of each photo.")
    }

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
