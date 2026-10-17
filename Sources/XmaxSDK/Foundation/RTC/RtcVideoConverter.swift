import CoreMedia
import Foundation
@preconcurrency import AgoraRtcKit

/// 保存声网外部视频帧及其连续像素数据。
final class RtcVideoFrame {

    // RTC 资源
    let value: AgoraVideoFrame

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

    /// 复用不可变像素时，仅更新时间戳和方向。
    func updateMetadata(from frame: VideoFrame) {
        value.time = CMTime(value: frame.timestampUs, timescale: 1000000)
        value.rotation = Int32(frame.rotation.rawValue)
    }
}

/// 为显式声明像素不变的视频帧复用 RTC 数据。
final class RtcVideoFrameCache {

    // 帧缓存
    private var cachedFrame: (id: UUID, frame: RtcVideoFrame)?

    func frame(for frame: VideoFrame) throws -> RtcVideoFrame {
        if let id = frame.bufferReuseID, let cachedFrame, cachedFrame.id == id {
            cachedFrame.frame.updateMetadata(from: frame)
            return cachedFrame.frame
        }

        let converted = try RtcVideoConverter.convertFrame(frame)
        cachedFrame = frame.bufferReuseID.map { ($0, converted) }
        return converted
    }

    func removeAll() {
        cachedFrame = nil
    }
}

/// 在中性视频模型与声网类型之间转换。
enum RtcVideoConverter {
    static func convertFrame(_ frame: VideoFrame) throws -> RtcVideoFrame {
        try RtcVideoFrame(frame: frame)
    }

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
