//
//  RtcRemoteVideoSink.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import AgoraRtcKit

/// 将声网解码帧复制到自有缓冲区，供异步渲染和插帧使用。
final class RtcRemoteVideoSink: NSObject, AgoraVideoFrameDelegate, @unchecked Sendable {

    /// 事件回调
    private let frameListener: @Sendable (UInt, String, RealtimeVideoFrame) -> Void

    /// 缓冲区资源
    private let lock = NSLock()
    private var pool: CVPixelBufferPool?
    private var dimensions = CGSize.zero
    private var pixelFormat: OSType = 0

    /// 创建远端解码帧接收器。
    ///
    /// - Parameter frameListener: 接收数字用户标识、频道标识和自有像素缓冲区的回调。
    init(frameListener: @escaping @Sendable (UInt, String, RealtimeVideoFrame) -> Void) {
        self.frameListener = frameListener
    }

    /// 指定远端帧使用 NV12 像素缓冲区。
    ///
    /// - Returns: NV12 视频帧格式。
    func getVideoFormatPreference() -> AgoraVideoFormat { .cvPixelNV12 }
    /// 指定在 RTC 渲染前接收解码帧。
    ///
    /// - Returns: 渲染前帧观察位置。
    func getObservedFramePosition() -> AgoraVideoFramePosition { .preRenderer }
    /// 指定回调只读取 RTC 原始帧。
    ///
    /// - Returns: 只读处理模式。
    func getVideoFrameProcessMode() -> AgoraVideoFrameProcessMode { .readOnly }
    /// 要求 RTC 在回调前将旋转应用到像素。
    ///
    /// - Returns: 始终返回 `true`。
    func getRotationApplied() -> Bool { true }
    /// 要求 RTC 保留未镜像的解码帧。
    ///
    /// - Returns: 始终返回 `false`。
    func getMirrorApplied() -> Bool { false }

    /// 复制解码缓冲区并回调可异步持有的远端帧。
    ///
    /// - Parameters:
    ///   - frame: 声网提供的解码帧。
    ///   - uid: 远端用户数字标识。
    ///   - channelId: 帧所属频道标识。
    /// - Returns: 始终返回 `true`，不阻止 RTC 继续处理该帧。
    func onRenderVideoFrame(_ frame: AgoraOutputVideoFrame, uid: UInt, channelId: String) -> Bool {
        guard let source = frame.pixelBuffer,
              let buffer = lock.withLock({ copy(source) }) else { return true }

        frameListener(uid, channelId, RealtimeVideoFrame(
            pixelBuffer: buffer,
            presentationTimeStamp: CMTime(value: frame.renderTimeMs, timescale: 1000)
        ))
        return true
    }

    /// 将双平面像素数据和附件复制到自有缓冲区。
    ///
    /// - Parameter source: 源像素缓冲区。
    /// - Returns: 可独立持有的复制缓冲区；布局不支持或分配失败时返回 `nil`。
    private func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let size = CGSize(width: width, height: height)
        let format = CVPixelBufferGetPixelFormatType(source)
        guard CVPixelBufferGetPlaneCount(source) == 2 else { return nil }
        if pool == nil || dimensions != size || pixelFormat != format {
            let attributes: [CFString: Any] = [
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: CVPixelBufferGetPixelFormatType(source),
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true
            ]
            guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else { return nil }
            dimensions = size
            pixelFormat = format
        }
        guard let pool else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess,
              let output else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        for plane in 0..<CVPixelBufferGetPlaneCount(source) {
            guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                  let dst = CVPixelBufferGetBaseAddressOfPlane(output, plane) else { return nil }
            let srcStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            let dstStride = CVPixelBufferGetBytesPerRowOfPlane(output, plane)
            let bytes = min(srcStride, dstStride)
            for row in 0..<CVPixelBufferGetHeightOfPlane(source, plane) {
                memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), bytes)
            }
        }
        CVBufferPropagateAttachments(source, output)
        return output
    }
}
