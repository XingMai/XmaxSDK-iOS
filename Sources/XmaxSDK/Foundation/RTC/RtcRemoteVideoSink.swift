//
//  RtcRemoteVideoSink.swift
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
@preconcurrency import AgoraRtcKit

/// Copies Agora decoded frames into buffers safe for asynchronous rendering.
final class RtcRemoteVideoSink: NSObject, AgoraVideoFrameDelegate, @unchecked Sendable {

    /// The handler receiving a numeric UID, channel, and SDK-owned buffer.
    private let frameListener: @Sendable (UInt, String, RealtimeVideoFrame) -> Void

    /// The lock protecting the remote pixel buffer pool.
    private let lock = NSLock()

    /// The reusable remote frame buffer pool.
    private var pool: CVPixelBufferPool?

    /// The current pool dimensions, in pixels.
    private var dimensions = CGSize.zero

    /// The current pool pixel format.
    private var pixelFormat: OSType = 0

    /// Creates a remote decoded frame receiver.
    init(
        frameListener: @escaping @Sendable (UInt, String, RealtimeVideoFrame) -> Void
    ) {
        self.frameListener = frameListener
    }

    /// Requests decoded frames as NV12 pixel buffers.
    ///
    /// - Returns: The NV12 video format.
    func getVideoFormatPreference() -> AgoraVideoFormat {
        .cvPixelNV12
    }

    /// Requests decoded frames before RTC rendering.
    ///
    /// - Returns: The pre-render frame observation position.
    func getObservedFramePosition() -> AgoraVideoFramePosition {
        .preRenderer
    }

    /// Requests read-only frame callbacks.
    ///
    /// - Returns: The read-only processing mode.
    func getVideoFrameProcessMode() -> AgoraVideoFrameProcessMode {
        .readOnly
    }

    /// Requests rotation be applied to pixels before delivery.
    ///
    /// - Returns: Always `true`.
    func getRotationApplied() -> Bool {
        true
    }

    /// Requests unmirrored decoded frames.
    ///
    /// - Returns: Always `false`.
    func getMirrorApplied() -> Bool {
        false
    }

    /// Delivers a copy of a decoded frame for asynchronous use.
    ///
    /// - Parameters:
    ///   - frame: The Agora decoded frame.
    ///   - uid: The remote numeric UID.
    ///   - channelId: The frame's channel identifier.
    ///
    /// - Returns: Always `true`, allowing RTC processing to continue.
    func onRenderVideoFrame(
        _ frame: AgoraOutputVideoFrame,
        uid: UInt,
        channelId: String
    ) -> Bool {
        guard let source = frame.pixelBuffer,
            let buffer = lock.withLock({
                copy(source)
            })
        else {
            return true
        }

        frameListener(
            uid,
            channelId,
            RealtimeVideoFrame(
                pixelBuffer: buffer,
                presentationTimeStamp: CMTime(
                    value: frame.renderTimeMs,
                    timescale: 1000
                )
            )
        )
        return true
    }

    /// Copies biplanar pixels and attachments into an owned buffer.
    ///
    /// - Parameter source: The source pixel buffer.
    ///
    /// - Returns: An owned copy, or `nil` if allocation fails or the layout is unsupported.
    private func copy(
        _ source: CVPixelBuffer
    ) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let size = CGSize(
            width: width,
            height: height
        )
        let format = CVPixelBufferGetPixelFormatType(source)
        guard CVPixelBufferGetPlaneCount(source) == 2 else {
            return nil
        }

        if pool == nil || dimensions != size || pixelFormat != format {
            let attributes: [CFString: Any] = [
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: CVPixelBufferGetPixelFormatType(source),
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true
            ]
            guard
                CVPixelBufferPoolCreate(
                    nil,
                    nil,
                    attributes as CFDictionary,
                    &pool
                ) == kCVReturnSuccess
            else {
                return nil
            }

            dimensions = size
            pixelFormat = format
        }

        guard let pool else {
            return nil
        }

        var output: CVPixelBuffer?
        guard
            CVPixelBufferPoolCreatePixelBuffer(
                nil,
                pool,
                &output
            ) == kCVReturnSuccess,
            let output
        else {
            return nil
        }

        CVPixelBufferLockBaseAddress(
            source,
            .readOnly
        )
        CVPixelBufferLockBaseAddress(
            output,
            []
        )
        defer {
            CVPixelBufferUnlockBaseAddress(
                output,
                []
            )
            CVPixelBufferUnlockBaseAddress(
                source,
                .readOnly
            )
        }

        for plane in 0..<CVPixelBufferGetPlaneCount(source) {
            guard
                let src = CVPixelBufferGetBaseAddressOfPlane(
                    source,
                    plane
                ),
                let dst = CVPixelBufferGetBaseAddressOfPlane(
                    output,
                    plane
                )
            else {
                return nil
            }

            let srcStride = CVPixelBufferGetBytesPerRowOfPlane(
                source,
                plane
            )
            let dstStride = CVPixelBufferGetBytesPerRowOfPlane(
                output,
                plane
            )
            let bytes = min(
                srcStride,
                dstStride
            )

            for row
                in 0..<CVPixelBufferGetHeightOfPlane(
                    source,
                    plane
                )
            {
                memcpy(
                    dst.advanced(by: row * dstStride),
                    src.advanced(by: row * srcStride),
                    bytes
                )
            }
        }

        CVBufferPropagateAttachments(
            source,
            output
        )
        return output
    }
}
