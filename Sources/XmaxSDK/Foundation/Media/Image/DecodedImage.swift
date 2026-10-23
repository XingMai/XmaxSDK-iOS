//
//  DecodedImage.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@preconcurrency import CoreGraphics

/// An orientation-corrected, decoded image.
protocol DecodedImage: Sendable {

    /// The decoded pixel dimensions.
    var size: CGSize {
        get
    }

    /// Creates a reusable frame by center-cropping and scaling to the requested dimensions.
    ///
    /// - Parameters:
    ///   - width: The target width, in pixels.
    ///   - height: The target height, in pixels.
    ///
    /// - Returns: A BGRA frame with a reuse identifier and a zero timestamp.
    ///
    /// - Throws: An error if dimensions are invalid, allocation overflows, or pixel rendering
    ///   fails.
    func makeVideoFrame(
        width: Int,
        height: Int
    ) throws -> VideoFrame
}

/// A decoded Core Graphics image that produces video frames.
final class CoreGraphicsDecodedImage: DecodedImage, @unchecked Sendable {

    /// The decoded image pixels.
    private let image: CGImage

    /// The decoded dimensions, in pixels.
    let size: CGSize

    /// Creates a decoded image with its orientation already applied.
    ///
    /// - Parameter image: The source image for cropping and scaling.
    init(
        image: CGImage
    ) {
        self.image = image
        size = CGSize(
            width: image.width,
            height: image.height
        )
    }

    /// Creates a reusable frame by center-cropping and scaling to the requested dimensions.
    ///
    /// - Parameters:
    ///   - width: The target width, in pixels.
    ///   - height: The target height, in pixels.
    ///
    /// - Returns: A BGRA frame with a reuse identifier and a zero timestamp.
    ///
    /// - Throws: An error if dimensions are invalid, allocation overflows, or pixel rendering
    ///   fails.
    func makeVideoFrame(
        width: Int,
        height: Int
    ) throws -> VideoFrame {
        guard width > 0, height > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image width and height must be finite numbers " + "greater than zero"
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
            cropRect.height == CGFloat(image.height)
        {
            sourceImage = image
        } else {
            guard let croppedImage = image.cropping(to: cropRect) else {
                throw Self.processingError("Failed to crop source image")
            }
            sourceImage = croppedImage
        }

        let (pixelCount, pixelOverflow) =
            width
            .multipliedReportingOverflow(by: height)
        guard !pixelOverflow else {
            throw Self.processingError("Image dimensions are too large")
        }
        let (byteCount, byteOverflow) =
            pixelCount
            .multipliedReportingOverflow(by: 4)
        guard !byteOverflow else {
            throw Self.processingError("Image dimensions are too large")
        }

        let bytesPerRow = try Self.bytesPerRow(width: width)
        var data = Data(count: byteCount)
        let bitmapInfo =
            CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
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
                )
            else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(
                sourceImage,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: height
                )
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

    /// Resolves a centered crop preserving the target aspect ratio.
    ///
    /// - Parameters:
    ///   - sourceWidth: The source width, in pixels.
    ///   - sourceHeight: The source height, in pixels.
    ///   - targetWidth: The output width, in pixels.
    ///   - targetHeight: The output height, in pixels.
    ///
    /// - Returns: An integer crop rectangle in source image coordinates.
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

    /// Calculates the row stride for a BGRA image.
    ///
    /// - Parameter width: The image width, in pixels.
    ///
    /// - Returns: The row size for four-byte pixels.
    ///
    /// - Throws: A media error if the row size overflows.
    static func bytesPerRow(
        width: Int
    ) throws -> Int {
        let (value, overflow) = width.multipliedReportingOverflow(by: 4)
        guard !overflow else {
            throw processingError("Image dimensions are too large")
        }
        return value
    }

    /// Creates an image processing error.
    ///
    /// - Parameter message: The image processing failure description.
    ///
    /// - Returns: An SDK media error.
    static func processingError(
        _ message: String
    ) -> XmaxError {
        XmaxError(
            code: .mediaError,
            message: message
        )
    }
}
