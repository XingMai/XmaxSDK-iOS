import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import AgoraRtcKit

/// 将声网解码帧复制到自有缓冲区，供异步渲染和插帧使用。
final class RtcRemoteVideoSink: NSObject, AgoraVideoFrameDelegate, @unchecked Sendable {

    // 事件回调
    private let frameListener: @Sendable (UInt, String, RealtimeVideoFrame) -> Void

    // 缓冲区资源
    private let lock = NSLock()
    private var pool: CVPixelBufferPool?
    private var dimensions = CGSize.zero
    private var pixelFormat: OSType = 0

    init(frameListener: @escaping @Sendable (UInt, String, RealtimeVideoFrame) -> Void) {
        self.frameListener = frameListener
    }

    func getVideoFormatPreference() -> AgoraVideoFormat { .cvPixelNV12 }
    func getObservedFramePosition() -> AgoraVideoFramePosition { .preRenderer }
    func getVideoFrameProcessMode() -> AgoraVideoFrameProcessMode { .readOnly }
    func getRotationApplied() -> Bool { true }
    func getMirrorApplied() -> Bool { false }

    func onRenderVideoFrame(_ frame: AgoraOutputVideoFrame, uid: UInt, channelId: String) -> Bool {
        guard let source = frame.pixelBuffer,
              let buffer = lock.withLock({ copy(source) }) else { return true }

        frameListener(uid, channelId, RealtimeVideoFrame(
            pixelBuffer: buffer,
            presentationTimeStamp: CMTime(value: frame.renderTimeMs, timescale: 1000)
        ))
        return true
    }

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
