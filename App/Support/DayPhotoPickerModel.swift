import Photos
import UIKit

/// How much of the Photos library Lamplight may read.
enum PhotoAccess: Equatable {
    case undecided
    case full
    /// The person shared only some photos.
    case limited
    case denied

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized: self = .full
        case .limited: self = .limited
        case .notDetermined: self = .undecided
        default: self = .denied
        }
    }

    var canRead: Bool { self == .full || self == .limited }

    static var current: PhotoAccess { PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }
}

/// One day's photos in the picker.
struct PickerDay: Identifiable, Equatable {
    let day: DayStamp
    /// True for the day of the entry, which is listed first.
    let isEntryDay: Bool
    /// Where the day's photos are in the library's list, which runs from the newest photo to the oldest.
    let range: Range<Int>

    var id: DayStamp { day }
    var count: Int { range.count }
}

/// What the "Add Photos" sheet shows: the photos from the day of the entry first, then every other day, newest first.
///
/// This reads the Photos library, so it needs access to it. The system's own picker needs none, but it can't be
/// grouped by day, which is why this exists. Without access the sheet offers that picker instead.
@MainActor
final class DayPhotoPickerModel: ObservableObject {
    /// As many photos as the system picker was allowed to hand over.
    static let limit = 12

    @Published private(set) var access: PhotoAccess
    @Published private(set) var days: [PickerDay] = []
    @Published private(set) var isLoading = false
    /// The photos chosen, as library identifiers, in the order they were tapped.
    @Published private(set) var selected: [String] = []

    let entryDay: DayStamp
    let calendar: DayCalendar
    let timeZone: TimeZone
    private var photos: PHFetchResult<PHAsset>?
    private var loadToken = 0
    private let thumbnailManager = PHCachingImageManager()

    init(entryDate: Date, timeZone: TimeZone, calendar: DayCalendar, access: PhotoAccess = .current) {
        self.access = access
        self.calendar = calendar
        self.timeZone = timeZone
        entryDay = calendar.stamp(for: entryDate, timeZone: timeZone)
    }

    // MARK: Access

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = PhotoAccess(status)
        await load()
    }

    /// The person may have changed the setting in Settings, or shared more photos. Read again if so.
    func refreshIfAccessChanged() async {
        guard PhotoAccess.current != access else { return }
        await load()
    }

    // MARK: Days

    /// Reads the library and lays out the days. The entry's day is found first, so it shows at once however big the
    /// library is. The rest are grouped in pieces, so the first screen shows before a big library has been read.
    func load() async {
        access = .current
        loadToken += 1
        let token = loadToken
        guard access.canRead else {
            photos = nil
            days = []
            isLoading = false
            return
        }
        isLoading = true

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        photos = result
        let count = result.count

        let calendar = self.calendar
        let timeZone = self.timeZone
        let entryRange = PhotoDays.range(of: entryDay, count: count, calendar: calendar, timeZone: timeZone) {
            result.object(at: $0).creationDate ?? .distantPast
        }
        let entry = PickerDay(day: entryDay, isEntryDay: true, range: entryRange)
        days = [entry]

        var grouper = PhotoDayGrouper(calendar: calendar, timeZone: timeZone)
        var index = 0
        while index < count {
            let end = min(index + 1500, count)
            let start = index
            let dates = await Task.detached(priority: .userInitiated) {
                (start..<end).map { result.object(at: $0).creationDate ?? .distantPast }
            }.value
            guard token == loadToken else { return }
            grouper.add(contentsOf: dates)
            days = [entry] + grouper.days
                .filter { $0.day != entry.day }
                .map { PickerDay(day: $0.day, isEntryDay: false, range: $0.range) }
            index = end
        }
        isLoading = false
    }

    /// The photo at a place in a day. Photos run oldest first within a day, as they were taken.
    func asset(in day: PickerDay, at position: Int) -> PHAsset? {
        guard let photos, position >= 0, position < day.count else { return nil }
        let index = day.range.upperBound - 1 - position
        guard index >= 0, index < photos.count else { return nil }
        return photos.object(at: index)
    }

    // MARK: Choosing

    var isFull: Bool { selected.count >= Self.limit }

    func number(of id: String) -> Int? {
        selected.firstIndex(of: id).map { $0 + 1 }
    }

    func toggle(_ id: String) {
        if let position = selected.firstIndex(of: id) {
            selected.remove(at: position)
        } else if !isFull {
            selected.append(id)
        }
    }

    // MARK: Pictures

    /// A small picture for the grid. It arrives rough first and sharp a moment later. Photos that live only in iCloud
    /// show the small version the library already has, and nothing is downloaded for the grid.
    func thumbnails(for asset: PHAsset, side: CGFloat) -> AsyncStream<UIImage> {
        let manager = thumbnailManager
        return AsyncStream { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            let request = manager.requestImage(
                for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options
            ) { image, info in
                if let image { continuation.yield(image) }
                let rough = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let stopped = (info?[PHImageCancelledKey] as? Bool) ?? false
                if !rough || stopped || info?[PHImageErrorKey] != nil { continuation.finish() }
            }
            continuation.onTermination = { _ in manager.cancelImageRequest(request) }
        }
    }

    /// The picked photos, as the files they are, in the order they were picked. One that can't be had, such as one
    /// still in iCloud with no connection, is left out.
    nonisolated static func imageData(for ids: [String]) async -> [Data] {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in assets[asset.localIdentifier] = asset }

        var all: [Data] = []
        for id in ids {
            guard let asset = assets[id], let data = await data(for: asset) else { continue }
            all.append(data)
        }
        return all
    }

    private nonisolated static func data(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            var answered = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                // Asked for once at full quality, so answered once. Guarded anyway: answering twice would trap.
                guard !answered else { return }
                answered = true
                continuation.resume(returning: data)
            }
        }
    }
}
