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

/// 使用 ImageIO 提供 SDK 内部图片解码能力。
final class ImageManager: ImageManaging, Sendable {

    /// 解码图片数据并应用图片方向，返回可重复处理的像素图像。
    ///
    /// - Parameter data: JPEG、PNG 等受支持格式的编码图片数据。
    /// - Returns: 已应用原始方向的解码图像。
    /// - Throws: 数据为空、格式不支持或图片解码失败时抛出错误。
    func decode(
        _ data: Data
    ) throws -> any DecodedImage {
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

    /// 创建图片处理错误。
    ///
    /// - Parameter message: 图片处理失败的可读说明。
    /// - Returns: 具有媒体错误码的 SDK 错误。
    private static func processingError(
        _ message: String
    ) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
