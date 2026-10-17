//
//  DecodedImage.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@preconcurrency import CoreGraphics

/// 表示 SDK 内部已经完成方向处理和像素解码的图片。
protocol DecodedImage: Sendable {

    // 图片尺寸
    /// 图片解码后的实际像素尺寸。
    var size: CGSize { get }

    /// 按目标比例居中裁剪并缩放图片，生成可复用的视频帧。
    ///
    /// - Parameters:
    ///   - width: 目标帧宽度，单位为像素。
    ///   - height: 目标帧高度，单位为像素。
    /// - Returns: 包含 BGRA 像素和缓冲区复用标识、初始时间戳为零的视频帧。
    /// - Throws: 尺寸无效、内存大小溢出或裁剪及像素绘制失败时抛出错误。
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

    /// 持有已应用方向信息的 Core Graphics 图片。
    ///
    /// - Parameter image: 作为后续裁剪和缩放源的像素图片。
    init(image: CGImage) {
        self.image = image
        size = CGSize(width: image.width, height: image.height)
    }

    /// 按目标比例居中裁剪并缩放图片，生成可复用的视频帧。
    ///
    /// - Parameters:
    ///   - width: 目标帧宽度，单位为像素。
    ///   - height: 目标帧高度，单位为像素。
    /// - Returns: 包含 BGRA 像素和缓冲区复用标识、初始时间戳为零的视频帧。
    /// - Throws: 尺寸无效、内存大小溢出或裁剪及像素绘制失败时抛出错误。
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

    /// 计算保留目标宽高比的居中裁剪区域。
    ///
    /// - Parameters:
    ///   - sourceWidth: 源图片宽度，单位为像素。
    ///   - sourceHeight: 源图片高度，单位为像素。
    ///   - targetWidth: 目标输出宽度，单位为像素。
    ///   - targetHeight: 目标输出高度，单位为像素。
    /// - Returns: 位于源图坐标系内的整数像素裁剪区域。
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
    /// 计算 BGRA 图像的每行字节数。
    ///
    /// - Parameter width: 图像宽度，单位为像素。
    /// - Returns: 每行四字节像素占用的总字节数。
    /// - Throws: 宽度计算产生整数溢出时抛出媒体错误。
    static func bytesPerRow(width: Int) throws -> Int {
        let (value, overflow) = width.multipliedReportingOverflow(by: 4)
        guard !overflow else {
            throw processingError("Image dimensions are too large")
        }
        return value
    }

    /// 创建图片处理错误。
    ///
    /// - Parameter message: 图片处理失败的可读说明。
    /// - Returns: 具有媒体错误码的 SDK 错误。
    static func processingError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
