import Foundation
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import CoreGraphics

/// 使用 Core Graphics 提供 SDK 内部图片处理能力。
final class ImageProvider: ImageProviding, Sendable {
    func makeProcessingSession(
        data: Data
    ) throws -> any ImageProcessingSession {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Self.processingError("Failed to create image source from data")
        }
        return try CoreGraphicsImageProcessingSession(source: source)
    }

    func resizeImageToFill(
        _ image: CGImage,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> CGImage {
        guard targetWidth > 0, targetHeight > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image width and height must be finite numbers greater than zero"
            )
        }

        let cropRect = Self.centerCropRect(
            sourceWidth: image.width,
            sourceHeight: image.height,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
        let sourceImage: CGImage
        if cropRect.width == CGFloat(image.width),
           cropRect.height == CGFloat(image.height) {
            sourceImage = image
        } else {
            guard let croppedImage = image.cropping(to: cropRect) else {
                throw Self.processingError("Failed to crop source image")
            }
            sourceImage = croppedImage
        }

        guard sourceImage.width != targetWidth || sourceImage.height != targetHeight else {
            return sourceImage
        }

        let bytesPerRow = try Self.bytesPerRow(width: targetWidth)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            throw Self.processingError("Failed to create image rendering context")
        }

        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(targetWidth),
                height: CGFloat(targetHeight)
            )
        )

        guard let outputImage = context.makeImage() else {
            throw Self.processingError("Failed to create resized image")
        }
        return outputImage
    }

    /// 计算保持目标宽高比的居中裁剪区域。
    static func centerCropRect(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> CGRect {
        let targetAspectRatio = Double(targetWidth) / Double(targetHeight)
        let sourceAspectRatio = Double(sourceWidth) / Double(sourceHeight)
        var cropWidth = sourceWidth
        var cropHeight = sourceHeight

        if sourceAspectRatio > targetAspectRatio {
            cropWidth = max(
                Int(floor(Double(sourceHeight) * targetAspectRatio)),
                1
            )
        } else if sourceAspectRatio < targetAspectRatio {
            cropHeight = max(
                Int(floor(Double(sourceWidth) / targetAspectRatio)),
                1
            )
        }

        return CGRect(
            x: CGFloat((sourceWidth - cropWidth) / 2),
            y: CGFloat((sourceHeight - cropHeight) / 2),
            width: CGFloat(cropWidth),
            height: CGFloat(cropHeight)
        )
    }

    private static func bytesPerRow(width: Int) throws -> Int {
        let (value, overflow) = width.multipliedReportingOverflow(by: 4)
        guard !overflow else {
            throw processingError("Image dimensions are too large")
        }
        return value
    }

    private static func processingError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}

/// 持有已经应用方向信息的 Core Graphics 图片并执行编码。
private final class CoreGraphicsImageProcessingSession:
    ImageProcessingSession,
    @unchecked Sendable {

    // 图片资源
    private let image: CGImage

    // 图片信息
    let metadata: ImageProcessingMetadata

    init(source: CGImageSource) throws {
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

        let sourceType = CGImageSourceGetType(source) as String?
        let contentType = sourceType
            .flatMap { UTType($0)?.preferredMIMEType }
            ?? "image/jpeg"
        self.image = image
        metadata = ImageProcessingMetadata(
            width: image.width,
            height: image.height,
            contentType: contentType.lowercased()
        )
    }

    func resizeAndEncode(
        width: Int,
        height: Int,
        requestedContentType: String,
        quality: Int
    ) throws -> ImageProcessingResult {
        let outputImage = try resizedImage(width: width, height: height)
        let contentType = Self.supportedContentType(requestedContentType)
        let data = try Self.encode(
            outputImage,
            contentType: contentType,
            quality: quality
        )
        return ImageProcessingResult(
            data: data,
            width: outputImage.width,
            height: outputImage.height,
            contentType: contentType
        )
    }

    func encodeJPEG(quality: Int) throws -> ImageProcessingResult {
        let contentType = "image/jpeg"
        return ImageProcessingResult(
            data: try Self.encode(
                image,
                contentType: contentType,
                quality: quality
            ),
            width: image.width,
            height: image.height,
            contentType: contentType
        )
    }
}

private extension CoreGraphicsImageProcessingSession {
    func resizedImage(width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0 else {
            throw Self.processingError("Image target size is invalid")
        }
        guard image.width != width || image.height != height else {
            return image
        }

        let (bytesPerRow, overflow) = width.multipliedReportingOverflow(by: 4)
        guard !overflow else {
            throw Self.processingError("Image dimensions are too large")
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            throw Self.processingError("Failed to create image rendering context")
        }

        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(width),
                height: CGFloat(height)
            )
        )
        guard let outputImage = context.makeImage() else {
            throw Self.processingError("Failed to create resized image")
        }
        return outputImage
    }

    static func supportedContentType(_ requested: String) -> String {
        let normalized = requested
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let type = UTType(mimeType: normalized),
              supportedDestinationTypes.contains(type.identifier) else {
            return "image/jpeg"
        }
        return type.preferredMIMEType?.lowercased() ?? "image/jpeg"
    }

    static func encode(
        _ image: CGImage,
        contentType: String,
        quality: Int
    ) throws -> Data {
        guard let type = UTType(mimeType: contentType) else {
            throw processingError("Image content type is unsupported")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw processingError("Failed to create image encoder")
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality:
                min(max(Double(quality) / 100, 0), 1)
        ]
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw processingError("Failed to encode image")
        }
        return data as Data
    }

    static var supportedDestinationTypes: Set<String> {
        let values = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return Set(values)
    }

    static func processingError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
