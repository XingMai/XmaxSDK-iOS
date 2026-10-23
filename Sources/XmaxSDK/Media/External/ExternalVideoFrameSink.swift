//
//  ExternalVideoFrameSink.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo
import Foundation

/// 串行接收外部帧，并在解绑时等待正在提交的帧结束。
final class ExternalVideoFrameSink: RealtimeExternalFrameSink, @unchecked Sendable {

    /// SDK 处理后的媒体规格，用作本地预览和调档基准。
    let videoFormat: RealtimeVideoFormat

    /// 接入方声明的原始供帧规格。
    private let sourceVideoFormat: RealtimeVideoFormat

    /// 将有效帧交付给预览及 RTC。
    private let frameListener: MediaVideoFrameListener

    /// 接收当前绑定的不可恢复错误。
    private let errorListener: XmaxErrorListener

    /// 保护绑定状态、时间戳及同步帧提交。
    private let lock = NSLock()

    /// 绑定是否仍接收帧，失败或解绑后不再恢复。
    private var active = true

    /// 最近接收的视频帧时间戳，单位为微秒。
    private var lastTimestampUs: Int64 = -1

    /// 创建绑定固定规格和帧处理回调的接收器。
    init(
        sourceVideoFormat: RealtimeVideoFormat,
        videoFormat: RealtimeVideoFormat,
        frameListener: @escaping MediaVideoFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.sourceVideoFormat = sourceVideoFormat
        self.videoFormat = videoFormat
        self.frameListener = frameListener
        self.errorListener = errorListener
    }

    /// 当前是否接受预览及生成用帧。
    var isRequestingFrames: Bool {
        lock.withLock { active }
    }

    /// 同步复制并交付有效帧；忽略无效或倒退的时间戳。
    ///
    /// - Parameters:
    ///   - pixelBuffer: 与源声明尺寸一致、方向已正确应用的像素缓冲区。
    ///   - timestamp: 持续递增的单调时间戳。
    func pushVideo(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    ) {
        guard timestamp.isNumeric, timestamp.epoch == 0, timestamp >= .zero else { return }
        let converted = CMTimeConvertScale(timestamp, timescale: 1000000, method: .roundTowardZero)
        guard converted.isNumeric, converted.value >= 0 else { return }

        lock.withLock {
            guard active, converted.value > lastTimestampUs else { return }
            do {
                guard CVPixelBufferGetWidth(pixelBuffer) == sourceVideoFormat.width,
                      CVPixelBufferGetHeight(pixelBuffer) == sourceVideoFormat.height else {
                    throw XmaxError(code: .mediaError, message: "External frame dimensions must match source.videoFormat")
                }
                let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
                guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                      pixelFormat == kCVPixelFormatType_32BGRA else {
                    throw XmaxError(code: .mediaError, message: "External video requires NV12 video-range (420v) or BGRA pixels")
                }
                let frame = try VideoFrameConverter.convert(
                    pixelBuffer: pixelBuffer,
                    outputWidth: videoFormat.width,
                    outputHeight: videoFormat.height,
                    rotation: .rotation0,
                    timestampUs: converted.value
                )
                lastTimestampUs = converted.value
                try frameListener(frame)
            } catch {
                active = false
                errorListener(XmaxError(code: .mediaError, message: "External video frame failed: \(error.localizedDescription)"))
            }
        }
    }

    /// 仅上报当前绑定的首次不可恢复错误。
    ///
    /// - Parameter error: 外部源的采集或处理错误。
    func reportError(
        _ error: any Error
    ) {
        lock.withLock {
            guard active else { return }
            active = false
            errorListener(XmaxError(code: .mediaError, message: "External video source failed: \(error.localizedDescription)"))
        }
    }

    /// 等待同步提交完成，并拒绝此后所有帧和错误通知。
    func invalidate() {
        lock.withLock { active = false }
    }
}
