@preconcurrency import CoreGraphics

/// 使用 Core Graphics 提供 SDK 内部图片处理能力。
final class ImageProvider: ImageProviding, Sendable {
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
