import Foundation
@preconcurrency import CoreGraphics

/// 表示 SDK 内部已经完成方向处理和像素解码的图片。
protocol DecodedImage: Sendable {

    /// 图片解码后的实际像素尺寸。
    var size: CGSize { get }

    /// 居中裁剪并转换为可供外部视频源重复使用的视频帧。
    func makeVideoFrame(
        width: Int,
        height: Int
    ) throws -> VideoFrame
}

/// 持有已经应用方向信息的 Core Graphics 图片并生成视频帧。
final class CoreGraphicsDecodedImage: DecodedImage, @unchecked Sendable {

    // 图片资源
    private let image: CGImage

    // 图片信息
    let size: CGSize

    init(image: CGImage) {
        self.image = image
        size = CGSize(width: image.width, height: image.height)
    }

    func makeVideoFrame(
        width: Int,
        height: Int
    ) throws -> VideoFrame {
        guard width > 0, height > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image width and height must be finite numbers " +
                    "greater than zero"
            )
        }

        let cropRect = Self.centerCropRect(
            sourceWidth: image.width,
            sourceHeight: image.height,
            targetWidth: width,
            targetHeight: height
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

        let (pixelCount, pixelOverflow) = width
            .multipliedReportingOverflow(by: height)
        guard !pixelOverflow else {
            throw Self.processingError("Image dimensions are too large")
        }
        let (byteCount, byteOverflow) = pixelCount
            .multipliedReportingOverflow(by: 4)
        guard !byteOverflow else {
            throw Self.processingError("Image dimensions are too large")
        }

        let bytesPerRow = try Self.bytesPerRow(width: width)
        var data = Data(count: byteCount)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        let didRender = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let address = bytes.baseAddress,
                  let context = CGContext(
                      data: address,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: bitmapInfo
                  ) else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(
                sourceImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard didRender else {
            throw Self.processingError("Failed to create image frame data")
        }

        return try VideoFrame(
            format: VideoFormat(
                width: width,
                height: height,
                pixelFormat: .bgra
            ),
            timestampUs: 0,
            planes: [
                VideoFramePlane(
                    data: data,
                    stride: bytesPerRow
                )
            ],
            bufferReuseID: UUID()
        )
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
}

private extension CoreGraphicsDecodedImage {
    static func bytesPerRow(width: Int) throws -> Int {
        let (value, overflow) = width.multipliedReportingOverflow(by: 4)
        guard !overflow else {
            throw processingError("Image dimensions are too large")
        }
        return value
    }

    static func processingError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
