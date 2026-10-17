import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ImageTools {
    struct Prepared {
        let data: Data
        let width: Int
        let height: Int
    }

    /// Shrinks a picked photo and saves it as JPEG. 2400 pixels on the long edge is sharp on an iPad
    /// and keeps a year of photos small enough for iCloud. Location data in the original is not kept.
    static func prepareForStorage(_ data: Data, maxPixel: Int = 2400, quality: CGFloat = 0.85) -> Prepared? {
        guard let image = downsampledImage(data, maxPixel: CGFloat(maxPixel)) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Prepared(data: output as Data, width: image.width, height: image.height)
    }

    /// A small version for lists and grids, made without decoding the whole photo.
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let image = downsampledImage(data, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func downsampledImage(_ data: Data, maxPixel: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
