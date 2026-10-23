//
//  ExternalVideoFrameConverter.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreVideo
import Foundation

/// 将外部像素缓冲区复制为 SDK 持有的中性视频帧，不改变画面内容。
enum ExternalVideoFrameConverter {

    /// 校验像素规格并复制平面，保留行跨度。
    ///
    /// - Parameters:
    ///   - pixelBuffer: 已处理方向的 NV12 video-range 或 BGRA 缓冲区。
    ///   - videoFormat: 本次绑定要求的媒体规格。
    ///   - timestampUs: 单调时间戳，单位为微秒。
    /// - Returns: 不再依赖外部缓冲区存储的视频帧。
    /// - Throws: 尺寸、像素格式或平面布局无效时抛出媒体错误。
    static func convert(
        _ pixelBuffer: CVPixelBuffer,
        videoFormat: RealtimeVideoFormat,
        timestampUs: Int64
    ) throws -> VideoFrame {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width == videoFormat.width, height == videoFormat.height else {
            throw XmaxError(code: .mediaError, message: "External frame dimensions must match sink.videoFormat")
        }

        let format: VideoPixelFormat
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            format = .nv12
        case kCVPixelFormatType_32BGRA:
            format = .bgra
        default:
            throw XmaxError(code: .mediaError, message: "External video requires NV12 video-range (420v) or BGRA pixels")
        }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            throw XmaxError(code: .mediaError, message: "Failed to lock external video pixels")
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let planes: [VideoFramePlane]
        if format == .nv12 {
            guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else {
                throw XmaxError(code: .mediaError, message: "External NV12 video requires two planes")
            }
            planes = try (0..<2).map { index in
                let rows = index == 0 ? height : height / 2
                guard CVPixelBufferGetWidthOfPlane(pixelBuffer, index) == (index == 0 ? width : width / 2),
                      CVPixelBufferGetHeightOfPlane(pixelBuffer, index) == rows else {
                    throw XmaxError(code: .mediaError, message: "Invalid external NV12 plane dimensions")
                }
                return try copyPlane(
                    CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, index),
                    stride: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, index),
                    rows: rows,
                    minimumStride: width
                )
            }
        } else {
            planes = [try copyPlane(
                CVPixelBufferGetBaseAddress(pixelBuffer),
                stride: CVPixelBufferGetBytesPerRow(pixelBuffer),
                rows: height,
                minimumStride: width * 4
            )]
        }

        return try VideoFrame(
            format: VideoFormat(width: width, height: height, pixelFormat: format),
            timestampUs: timestampUs,
            planes: planes
        )
    }

    /// 复制布局有效的像素平面。
    ///
    /// - Parameters:
    ///   - address: 平面首地址。
    ///   - stride: 每行实际字节数。
    ///   - rows: 平面行数。
    ///   - minimumStride: 每行有效像素需要的最小字节数。
    /// - Returns: 拥有独立字节存储的像素平面。
    /// - Throws: 地址或平面大小无效时抛出媒体错误。
    private static func copyPlane(
        _ address: UnsafeMutableRawPointer?,
        stride: Int,
        rows: Int,
        minimumStride: Int
    ) throws -> VideoFramePlane {
        let (count, overflow) = stride.multipliedReportingOverflow(by: rows)
        guard let address, stride >= minimumStride, rows > 0, !overflow, count > 0 else {
            throw XmaxError(code: .mediaError, message: "Invalid external video plane layout")
        }
        return try VideoFramePlane(data: Data(bytes: address, count: count), stride: stride)
    }
}
