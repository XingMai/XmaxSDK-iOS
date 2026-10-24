//
//  ImageManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import ImageIO

/// An ImageIO image decoder.
final class ImageManager: ImageManaging, Sendable {

    /// Decodes image data and applies its orientation.
    ///
    /// - Parameter data: Encoded image data, such as JPEG or PNG.
    ///
    /// - Returns: The orientation-corrected decoded image.
    ///
    /// - Throws: An error if data is empty, unsupported, or cannot be decoded.
    func decode(
        _ data: Data
    ) throws -> any DecodedImage {
        guard !data.isEmpty,
            let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
            )
        else {
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
            ] as? NSNumber
        else {
            throw Self.processingError("Failed to read image metadata")
        }

        let maximumPixelSize = max(
            rawWidth.intValue,
            rawHeight.intValue
        )
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
            )
        else {
            throw Self.processingError("Failed to decode image")
        }

        return CoreGraphicsDecodedImage(image: image)
    }

    /// Creates an image processing error.
    ///
    /// - Parameter message: The image processing failure description.
    ///
    /// - Returns: An SDK media error.
    private static func processingError(
        _ message: String
    ) -> XmaxError {
        XmaxError(
            code: .mediaError,
            message: message
        )
    }
}
