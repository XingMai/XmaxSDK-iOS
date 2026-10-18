//
//  RtcVideoConverter.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import Foundation
@preconcurrency import AgoraRtcKit

/// 保存声网外部视频帧及其连续像素数据。
final class RtcVideoFrame {

    /// RTC 资源
    let value: AgoraVideoFrame

    /// 校验视频平面并复制为声网外部视频帧。
    ///
    /// - Parameter frame: 包含像素平面、尺寸和时间戳的源帧。
    /// - Throws: 尺寸超出平台范围、平面数量或数据布局无效时抛出错误。
    init(frame: VideoFrame) throws {
        let width = frame.format.width
        let height = frame.format.height
        guard let rtcWidth = Int32(exactly: width),
              let rtcHeight = Int32(exactly: height) else {
            throw XmaxError(code: .invalidConfiguration, message: "Video frame dimensions exceed the RTC range")
        }

        let layout: [(bytes: Int, rows: Int)]
        switch frame.format.pixelFormat {
        case .i420:
            layout = [(width, height), ((width + 1) / 2, (height + 1) / 2), ((width + 1) / 2, (height + 1) / 2)]
        case .nv12, .nv21:
            layout = [(width, height), (((width + 1) / 2) * 2, (height + 1) / 2)]
        case .rgba, .bgra, .argb:
            layout = [(width * 4, height)]
        }
        guard frame.planes.count == layout.count else {
            throw XmaxError(code: .invalidConfiguration, message: "Video frame requires \(layout.count) data planes")
        }

        var data = Data()
        for (plane, size) in zip(frame.planes, layout) {
            guard plane.stride >= size.bytes,
                  size.rows > 0,
                  plane.byteLength >= size.bytes,
                  size.rows - 1 <= (plane.byteLength - size.bytes) / plane.stride else {
                throw XmaxError(code: .invalidConfiguration, message: "Video frame plane is smaller than its dimensions")
            }
            plane.data.withUnsafeBytes { bytes in
                for row in 0..<size.rows {
                    let start = bytes.baseAddress!.advanced(by: plane.byteOffset + row * plane.stride)
                    data.append(start.assumingMemoryBound(to: UInt8.self), count: size.bytes)
                }
            }
        }

        value = AgoraVideoFrame()
        value.format = RtcVideoConverter.convertPixelFormat(frame.format.pixelFormat)
        value.strideInPixels = rtcWidth
        value.height = rtcHeight
        value.dataBuf = data
        updateMetadata(from: frame)
    }

    /// 复用像素数据时更新时间戳和旋转信息。
    ///
    /// - Parameter frame: 提供最新时间戳和旋转标记的视频帧。
    func updateMetadata(from frame: VideoFrame) {
        value.time = CMTime(value: frame.timestampUs, timescale: 1000000)
        value.rotation = Int32(frame.rotation.rawValue)
    }
}

/// 为显式声明像素不变的视频帧复用 RTC 数据。
final class RtcVideoFrameCache {

    /// 帧缓存
    private var cachedFrame: (id: UUID, frame: RtcVideoFrame)?

    /// 获取源帧的 RTC 表示，并按像素复用标识缓存数据。
    ///
    /// - Parameter frame: 需要适配的源视频帧。
    /// - Returns: 像素数据已准备好的 RTC 帧。
    /// - Throws: 帧尺寸或像素数据布局无效时抛出错误。
    func frame(for frame: VideoFrame) throws -> RtcVideoFrame {
        if let id = frame.bufferReuseID, let cachedFrame, cachedFrame.id == id {
            cachedFrame.frame.updateMetadata(from: frame)
            return cachedFrame.frame
        }

        let converted = try RtcVideoConverter.convertFrame(frame)
        cachedFrame = frame.bufferReuseID.map { ($0, converted) }
        return converted
    }

    /// 清除已缓存的 RTC 帧及其像素数据。
    func removeAll() {
        cachedFrame = nil
    }
}

/// 在中性视频模型与声网类型之间转换。
enum RtcVideoConverter {
    /// 将 SDK 视频帧转换为声网外部帧。
    ///
    /// - Parameter frame: 待转换的 SDK 视频帧。
    /// - Returns: 持有连续像素数据的 RTC 帧。
    /// - Throws: 帧尺寸或像素数据布局无效时抛出错误。
    static func convertFrame(_ frame: VideoFrame) throws -> RtcVideoFrame {
        try RtcVideoFrame(frame: frame)
    }

    /// 将 SDK 编码参数转换为声网编码配置。
    ///
    /// - Parameter configuration: 尺寸、帧率、码率上下界和编码偏好。
    /// - Returns: 初始镜像关闭、方向自适应的声网编码配置。
    static func makeEncoderConfiguration(_ configuration: VideoEncodingConfiguration) -> AgoraVideoEncoderConfiguration {
        let result = AgoraVideoEncoderConfiguration(
            size: CGSize(width: configuration.width, height: configuration.height),
            frameRate: configuration.frameRate,
            bitrate: max(0, configuration.maximumBitrate),
            orientationMode: .adaptative,
            mirrorMode: .disabled
        )
        result.minBitrate = configuration.minimumBitrate
        result.degradationPreference = switch configuration.encoderPreference {
        case .auto: .maintainAuto
        case .maintainFramerate: .maintainFramerate
        case .maintainQuality: .maintainQuality
        }
        return result
    }

    /// 映射 SDK 像素格式到声网外部帧格式。
    ///
    /// - Parameter format: SDK 视频像素格式。
    /// - Returns: 对应的声网像素格式标识。
    static func convertPixelFormat(_ format: VideoPixelFormat) -> Int {
        switch format {
        case .i420: 1
        case .bgra: 2
        case .nv21: 3
        case .rgba: 4
        case .argb: 7
        case .nv12: 8
        }
    }
}
