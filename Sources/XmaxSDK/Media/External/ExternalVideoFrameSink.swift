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

    /// 本次绑定要求的媒体规格。
    let videoFormat: RealtimeVideoFormat

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
        videoFormat: RealtimeVideoFormat,
        frameListener: @escaping MediaVideoFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
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
    ///   - pixelBuffer: 与供帧规格一致的像素缓冲区。
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
                let frame = try ExternalVideoFrameConverter.convert(
                    pixelBuffer,
                    videoFormat: videoFormat,
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
