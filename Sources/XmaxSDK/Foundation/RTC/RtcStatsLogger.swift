import Foundation
@preconcurrency import AgoraRtcKit

/// 将声网 RTC 运行统计输出为统一的 Xmax 调试日志。
enum RtcStatsLogger {
    static func logLocalStreamStats(_ video: AgoraRtcLocalVideoStats) {
        XmaxLogger.rtc.debug(message: """
        本地视频发送 (Local Video Uplink)
        ├─ \(XmaxLogger.localized("分辨率：", "Resolution: "))\(video.encodedFrameWidth) × \(video.encodedFrameHeight)
        ├─ \(XmaxLogger.localized("发送码率：", "Send Bitrate: "))\(video.sentBitrate) kbps
        ├─ \(XmaxLogger.localized("采集帧率：", "Capture Frame Rate: "))\(video.captureFrameRate) fps
        ├─ \(XmaxLogger.localized("编码帧率：", "Encode Frame Rate: "))\(video.encoderOutputFrameRate) fps
        ├─ \(XmaxLogger.localized("发送帧率：", "Send Frame Rate: "))\(video.sentFrameRate) fps
        └─ \(XmaxLogger.localized("视频丢包率：", "Video Packet Loss: "))\(video.txPacketLossRate)%
        """, option: .performance)
    }

    static func logRemoteStreamStats(_ video: AgoraRtcRemoteVideoStats) {
        XmaxLogger.rtc.debug(message: """
        远端视频接收 (Remote Video Downlink)
        ├─ \(XmaxLogger.localized("分辨率：", "Resolution: "))\(video.width) × \(video.height)
        ├─ \(XmaxLogger.localized("接收码率：", "Receive Bitrate: "))\(video.receivedBitrate) kbps
        ├─ \(XmaxLogger.localized("解码帧率：", "Decode Frame Rate: "))\(video.decoderOutputFrameRate) fps
        ├─ \(XmaxLogger.localized("渲染帧率：", "Render Frame Rate: "))\(video.rendererOutputFrameRate) fps
        ├─ \(XmaxLogger.localized("视频丢包率：", "Video Packet Loss: "))\(video.packetLossRate)%
        ├─ \(XmaxLogger.localized("卡顿时长：", "Stall Duration: "))\(video.totalFrozenTime) ms
        └─ \(XmaxLogger.localized("端到端时延：", "End-to-End Delay: "))\(video.e2eDelay) ms
        """, option: .performance)
    }
}
