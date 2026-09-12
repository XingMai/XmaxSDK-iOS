import Foundation
@preconcurrency import VolcEngineRTC

/// 将火山 RTC 运行统计输出为统一的 Xmax 调试日志。
enum RtcStatsLogger {

    static func logLocalStreamStats(_ stats: ByteRTCLocalStreamStats) {
        XmaxLogger.rtc.debug(
            message: localStreamStatsMessage(stats),
            option: .performance
        )
    }

    static func logRemoteStreamStats(_ stats: ByteRTCRemoteStreamStats) {
        XmaxLogger.rtc.debug(
            message: remoteStreamStatsMessage(stats),
            option: .performance
        )
    }

    static func logNetworkQuality(
        localQuality: ByteRTCNetworkQualityStats,
        remoteQualities: [ByteRTCNetworkQualityStats]
    ) {
        XmaxLogger.rtc.debug(
            message: networkQualityMessage(
                localQuality: localQuality,
                remoteQualities: remoteQualities
            ),
            option: .performance
        )
    }

    static func logPerformanceAlarm(
        reason: ByteRTCPerformanceAlarmReason,
        data: ByteRTCSourceWantedData
    ) {
        XmaxLogger.rtc.debug(
            message: performanceAlarmMessage(reason: reason, data: data),
            option: .performance
        )
    }

    private static func localStreamStatsMessage(
        _ stats: ByteRTCLocalStreamStats
    ) -> String {
        let video = stats.videoStats
        return """
        本地视频发送 (Local Video Uplink)
        ├─ 分辨率 (Resolution)：\(video.encodedFrameWidth) × \(video.encodedFrameHeight)
        ├─ 发送码率 (Send Bitrate)：\(video.sentKBitrate) kbps
        ├─ 采集帧率 (Capture Frame Rate)：\(video.inputFrameRate) fps
        ├─ 编码帧率 (Encode Frame Rate)：\(video.encoderOutputFrameRate) fps
        ├─ 发送帧率 (Send Frame Rate)：\(video.sentFrameRate) fps
        ├─ 视频丢包率 (Video Packet Loss)：\(percentage(video.videoLossRate))
        ├─ 网络往返时延 (Round-Trip Time)：\(video.rtt) ms
        └─ 网络抖动 (Network Jitter)：\(video.jitter) ms
        """
    }

    private static func remoteStreamStatsMessage(
        _ stats: ByteRTCRemoteStreamStats
    ) -> String {
        let video = stats.videoStats
        return """
        远端视频接收 (Remote Video Downlink)
        ├─ 分辨率 (Resolution)：\(video.width) × \(video.height)
        ├─ 接收码率 (Receive Bitrate)：\(video.receivedKBitrate) kbps
        ├─ 解码帧率 (Decode Frame Rate)：\(video.decoderOutputFrameRate) fps
        ├─ 渲染帧率 (Render Frame Rate)：\(video.renderOutputFrameRate) fps
        ├─ 视频丢包率 (Video Packet Loss)：\(percentage(video.videoLossRate))
        ├─ 网络往返时延 (Round-Trip Time)：\(video.rtt) ms
        ├─ 卡顿次数 (Stall Count)：\(video.stallCount)
        ├─ 卡顿时长 (Stall Duration)：\(video.stallDuration) ms
        └─ 端到端时延 (End-to-End Delay)：\(video.e2eDelay) ms
        """
    }

    private static func networkQualityMessage(
        localQuality: ByteRTCNetworkQualityStats,
        remoteQualities: [ByteRTCNetworkQualityStats]
    ) -> String {
        let hasRemoteQuality = !remoteQualities.isEmpty
        let localBranch = hasRemoteQuality ? "├─" : "└─"
        let localIndent = hasRemoteQuality ? "│  " : "   "
        var lines = [
            "网络质量 (Network Quality Metrics)",
            "\(localBranch) 本地发送（上行）(Local Uplink)",
            "\(localIndent)├─ 质量 (Quality)：\(networkQualityName(localQuality.txQuality))",
            "\(localIndent)└─ \(networkMetrics(localQuality, includesRtt: true))"
        ]

        for (index, quality) in remoteQualities.enumerated() {
            let isLast = index == remoteQualities.count - 1
            let branch = isLast ? "└─" : "├─"
            let indent = isLast ? "   " : "│  "
            lines.append("\(branch) 远端接收（下行）(Remote Downlink)：\(quality.uid)")
            lines.append(
                "\(indent)├─ 质量 (Quality)：\(networkQualityName(quality.rxQuality))"
            )
            lines.append(
                "\(indent)└─ \(networkMetrics(quality, includesRtt: false))"
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func performanceAlarmMessage(
        reason: ByteRTCPerformanceAlarmReason,
        data: ByteRTCSourceWantedData
    ) -> String {
        var lines = ["性能告警 (Performance Alert)"]
        let state = performanceAlarmName(reason)
        if data.width > 0, data.height > 0, data.frameRate > 0 {
            lines.append("├─ 状态 (Status)：\(state)")
            lines.append(
                "└─ 建议 (Recommendation)：\(data.width) × \(data.height)，\(data.frameRate) fps"
            )
        } else {
            lines.append("└─ 状态 (Status)：\(state)")
        }
        return lines.joined(separator: "\n")
    }

    private static func networkMetrics(
        _ quality: ByteRTCNetworkQualityStats,
        includesRtt: Bool
    ) -> String {
        var metrics = ["丢包 (Packet Loss) \(percentage(quality.lossRatio))"]
        if includesRtt {
            metrics.append("RTT \(quality.rtt) ms")
        }
        metrics.append(
            "带宽 (Bandwidth) \(String(format: "%.0f", Double(quality.totalBandwidth) / 1_000)) kbps"
        )
        return "指标 (Metrics)：\(metrics.joined(separator: "，"))"
    }

    private static func networkQualityName(
        _ quality: ByteRTCNetworkQuality
    ) -> String {
        switch quality {
        case .excellent:
            "极好 (Excellent)"
        case .good:
            "良好 (Good)"
        case .poor:
            "较差 (Poor)"
        case .bad:
            "差 (Bad)"
        case .veryBad:
            "极差 (Very Bad)"
        case .down:
            "断网 (Disconnected)"
        default:
            "未知 (Unknown)"
        }
    }

    private static func performanceAlarmName(
        _ reason: ByteRTCPerformanceAlarmReason
    ) -> String {
        switch reason {
        case .bandwidthFallback:
            "网络受限 (Bandwidth Limited)"
        case .bandwidthResumed:
            "网络恢复 (Bandwidth Recovered)"
        case .fallback:
            "设备性能受限 (Device Performance Limited)"
        case .resumed:
            "设备性能恢复 (Device Performance Recovered)"
        default:
            "未知 (Unknown)"
        }
    }

    private static func percentage<T: BinaryFloatingPoint>(_ value: T) -> String {
        String(format: "%.2f%%", Double(value) * 100)
    }
}
