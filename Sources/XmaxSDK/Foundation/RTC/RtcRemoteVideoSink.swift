import Foundation
@preconcurrency import VolcEngineRTC

/// 接收一帧 RTC 远端解码视频数据的监听器。
typealias RtcRemoteVideoFrameListener = @Sendable (
    _ frame: RealtimeVideoFrame
) -> Void

/// 将火山 RTC 远端解码帧转换为 SDK 中性帧模型。
final class RtcRemoteVideoSink: NSObject,
    ByteRTCVideoSinkDelegate,
    @unchecked Sendable {

    // 事件监听
    private let frameListener: RtcRemoteVideoFrameListener

    init(frameListener: @escaping RtcRemoteVideoFrameListener) {
        self.frameListener = frameListener
    }

    func onFrame(_ videoFrame: any ByteRTCVideoFrame) {
        guard videoFrame.bufferType == ByteRTCVideoBufferType(rawValue: 1),
              let pixelBuffer = videoFrame.cvpixelbuffer else {
            return
        }
        frameListener(
            RealtimeVideoFrame(
                pixelBuffer: pixelBuffer,
                presentationTimeStamp: videoFrame.timestamp
            )
        )
    }
}
