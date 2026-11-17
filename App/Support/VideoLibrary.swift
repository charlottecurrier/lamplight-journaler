import AVFoundation
import Photos
import UIKit

/// Finds and plays the videos that entries link to. A linked video stays in the person's Photos library: the entry
/// holds a still frame and a `VideoLink`. All of this needs access to the library, and none of it runs until a video
/// is added or played.
enum VideoLibrary {
    /// Why a linked video can't be played.
    enum Problem: Error, Equatable {
        /// Lamplight may not read the Photos library.
        case noAccess
        /// The video isn't in the library on this device: deleted, or iCloud Photos is off here.
        case notFound
        /// The library has it but couldn't hand it over, such as with no connection.
        case unavailable
    }

    // MARK: Adding

    /// The name iCloud Photos gives each video on every device, by the name it has on this one. A video with no
    /// such name, as when iCloud Photos is off or only some photos are shared, is left out.
    static func cloudIDs(forLocalIDs ids: [String]) -> [String: String] {
        guard !ids.isEmpty, PhotoAccess.current.canRead else { return [:] }
        var found: [String: String] = [:]
        for (local, result) in PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: ids) {
            if case .success(let cloud) = result { found[local] = cloud.stringValue }
        }
        return found
    }

    /// A still frame of a video, as a JPEG. This is what the entry keeps and what other apps show.
    static func stillFrame(of asset: PHAsset, maxPixel: CGFloat = 2400) async -> Data? {
        let image: UIImage? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            var answered = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: maxPixel, height: maxPixel), contentMode: .aspectFit, options: options
            ) { image, _ in
                // Asked for once at full quality, so answered once. Guarded anyway: answering twice would trap.
                guard !answered else { return }
                answered = true
                continuation.resume(returning: image)
            }
        }
        return image?.jpegData(compressionQuality: 0.9)
    }

    // MARK: Playing

    /// The video a link points to, as the library on this device knows it. Tried by its name here first, then by its
    /// iCloud name, then by when it was taken and how long it is.
    static func asset(for link: VideoLink) -> Result<PHAsset, Problem> {
        guard PhotoAccess.current.canRead else { return .failure(.noAccess) }

        if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [link.localID], options: nil).firstObject,
           asset.mediaType == .video {
            return .success(asset)
        }
        if let cloud = link.cloudID {
            let identifier = PHCloudIdentifier(stringValue: cloud)
            let mapped = PHPhotoLibrary.shared().localIdentifierMappings(for: [identifier])[identifier]
            if case .success(let local)? = mapped,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [local], options: nil).firstObject {
                return .success(asset)
            }
        }
        if let taken = link.takenAt {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                PHAssetMediaType.video.rawValue,
                taken.addingTimeInterval(-1) as NSDate, taken.addingTimeInterval(1) as NSDate
            )
            var match: PHAsset?
            var matches = 0
            PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
                if abs(asset.duration - link.duration) < 0.5 {
                    match = asset
                    matches += 1
                }
            }
            // Two that fit are not a match. Guessing could play the wrong video.
            if matches == 1, let match { return .success(match) }
        }
        return .failure(.notFound)
    }

    /// Something to play for a video in the library. If the video is only in iCloud it is brought down, and
    /// `progress` is told how far along that is, from 0 to 1.
    static func playerItem(
        for asset: PHAsset, progress: @escaping @Sendable (Double) -> Void
    ) async -> Result<AVPlayerItem, Problem> {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            options.progressHandler = { fraction, _, _, _ in progress(fraction) }
            var answered = false
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                guard !answered else { return }
                answered = true
                if let item {
                    continuation.resume(returning: .success(item))
                } else {
                    continuation.resume(returning: .failure(.unavailable))
                }
            }
        }
    }
}
