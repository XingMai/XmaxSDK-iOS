import CoreMedia
import Foundation
import UIKit
@preconcurrency import VolcEngineRTC

/// 保存可同步推送给火山 RTC 的视频帧及其底层内存。
final class RtcVideoFrame {
    let value: ByteRTCVideoFrameData

    private let planeBuffers: [NSData]
    private let planeData: UnsafeMutablePointer<UnsafeMutableRawPointer?>
    private let planeStrides: UnsafeMutablePointer<Int32>

    init(
        frame: any VideoFrame,
        seiData: Data?
    ) throws {
        let expectedPlaneCount = Self.expectedPlaneCount(
            for: frame.format.pixelFormat
        )
        guard frame.planes.count == expectedPlaneCount else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame requires \(expectedPlaneCount) data planes"
            )
        }
        guard let width = Int32(exactly: frame.format.width),
              let height = Int32(exactly: frame.format.height) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame dimensions exceed the RTC range"
            )
        }

        let buffers = frame.planes.map { plane in
            let range = plane.byteOffset..<(plane.byteOffset + plane.byteLength)
            return NSData(data: plane.data.subdata(in: range))
        }
        let dataPointers = UnsafeMutablePointer<UnsafeMutableRawPointer?>
            .allocate(capacity: expectedPlaneCount)
        let stridePointers = UnsafeMutablePointer<Int32>
            .allocate(capacity: expectedPlaneCount)

        for index in 0..<expectedPlaneCount {
            guard let stride = Int32(exactly: frame.planes[index].stride) else {
                dataPointers.deinitialize(count: index)
                dataPointers.deallocate()
                stridePointers.deinitialize(count: index)
                stridePointers.deallocate()
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Video frame stride exceeds the RTC range"
                )
            }

            dataPointers.advanced(by: index).initialize(
                to: UnsafeMutableRawPointer(mutating: buffers[index].bytes)
            )
            stridePointers.advanced(by: index).initialize(to: stride)
        }

        let rtcFrame = ByteRTCVideoFrameData()
        rtcFrame.bufferType = .rawMemory
        rtcFrame.pixelFormat = RtcVideoConverter.convertPixelFormat(
            frame.format.pixelFormat
        )
        rtcFrame.contentType = .normalFrame
        rtcFrame.timestamp = CMTime(
            value: frame.timestampUs,
            timescale: 1_000_000
        )
        rtcFrame.width = width
        rtcFrame.height = height
        rtcFrame.rotation = RtcVideoConverter.convertRotation(frame.rotation)
        rtcFrame.seiData = seiData
        rtcFrame.numberOfPlanes = Int32(expectedPlaneCount)
        rtcFrame.planeDataArray = dataPointers
        rtcFrame.planeStrideArray = stridePointers

        value = rtcFrame
        planeBuffers = buffers
        planeData = dataPointers
        planeStrides = stridePointers
    }

    deinit {
        planeData.deinitialize(count: planeBuffers.count)
        planeData.deallocate()
        planeStrides.deinitialize(count: planeBuffers.count)
        planeStrides.deallocate()
    }

    private static func expectedPlaneCount(
        for pixelFormat: VideoPixelFormat
    ) -> Int {
        switch pixelFormat {
        case .i420:
            3
        case .nv12, .nv21:
            2
        case .rgba, .bgra, .argb:
            1
        }
    }
}

/// 在中性视频模型和火山 RTC 视频类型之间转换。
enum RtcVideoConverter {

    /// 创建由调用方同步推送的火山 RTC 视频帧。
    static func convertFrame(
        _ frame: any VideoFrame,
        seiData: Data? = nil
    ) throws -> RtcVideoFrame {
        try RtcVideoFrame(frame: frame, seiData: seiData)
    }

    /// 转换摄像头方向。
    static func convertCameraID(
        _ position: CameraPosition
    ) -> ByteRTCCameraID {
        switch position {
        case .front:
            .front
        case .back:
            .back
        }
    }

    /// 根据摄像头方向生成本地镜像策略。
    static func convertMirrorType(
        _ position: CameraPosition
    ) -> ByteRTCMirrorType {
        switch position {
        case .front:
            .renderAndEncoder
        case .back:
            .none
        }
    }

    /// 创建火山 RTC 渲染画布。
    static func makeCanvas(
        view: UIView?,
        contentMode: VideoContentMode
    ) -> ByteRTCVideoCanvas {
        let canvas = ByteRTCVideoCanvas()
        canvas.view = view
        canvas.renderMode = convertRenderMode(contentMode)
        canvas.backgroundColor = 0
        canvas.renderRotation = .rotation0
        return canvas
    }

    /// 创建火山 RTC 视频编码配置。
    static func makeEncoderConfiguration(
        _ configuration: VideoEncodingConfiguration
    ) -> ByteRTCVideoEncoderConfig {
        let rtcConfiguration = ByteRTCVideoEncoderConfig()
        rtcConfiguration.width = configuration.width
        rtcConfiguration.height = configuration.height
        rtcConfiguration.frameRate = configuration.frameRate
        rtcConfiguration.minBitrate = configuration.minimumBitrate
        rtcConfiguration.maxBitrate = configuration.maximumBitrate
        rtcConfiguration.encoderPreference = .maintainFramerate
        return rtcConfiguration
    }

    static func convertPixelFormat(
        _ pixelFormat: VideoPixelFormat
    ) -> ByteRTCVideoPixelFormat {
        switch pixelFormat {
        case .i420:
            .I420
        case .nv12:
            .NV12
        case .nv21:
            .NV21
        case .rgba:
            .RGBA
        case .bgra:
            .BGRA
        case .argb:
            .ARGB
        }
    }

    static func convertRotation(
        _ rotation: VideoRotation
    ) -> ByteRTCVideoRotation {
        switch rotation {
        case .rotation0:
            .rotation0
        case .rotation90:
            .rotation90
        case .rotation180:
            .rotation180
        case .rotation270:
            .rotation270
        }
    }

    private static func convertRenderMode(
        _ contentMode: VideoContentMode
    ) -> ByteRTCRenderMode {
        switch contentMode {
        case .fit:
            .fit
        case .fill:
            .hidden
        }
    }
}
