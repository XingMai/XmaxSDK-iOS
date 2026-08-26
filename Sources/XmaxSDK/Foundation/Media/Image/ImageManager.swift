import Foundation
import ImageIO

/// 使用 ImageIO 提供 SDK 内部图片解码能力。
final class ImageManager: ImageManaging, Sendable {
    func decode(_ data: Data) throws -> any DecodedImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Self.processingError("Failed to create image source from data")
        }
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let rawWidth = properties[
                  kCGImagePropertyPixelWidth
              ] as? NSNumber,
              let rawHeight = properties[
                  kCGImagePropertyPixelHeight
              ] as? NSNumber else {
            throw Self.processingError("Failed to read image metadata")
        }

        let maximumPixelSize = max(rawWidth.intValue, rawHeight.intValue)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard maximumPixelSize > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  options as CFDictionary
              ) else {
            throw Self.processingError("Failed to decode image")
        }
        return CoreGraphicsDecodedImage(image: image)
    }

    private static func processingError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
