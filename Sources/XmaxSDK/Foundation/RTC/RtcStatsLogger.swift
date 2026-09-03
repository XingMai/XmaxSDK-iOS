import Foundation
@preconcurrency import VolcEngineRTC

/// 将火山 RTC 运行统计输出为统一的 Xmax 调试日志。
enum RtcStatsLogger {

    // 日志配置
    private static let category = "RTC"

    static func logLocalStreamStats(_ stats: ByteRTCLocalStreamStats) {
        XmaxLogger.debug(
            category: category,
            message: localStreamStatsMessage(stats),
            option: .performance
        )
    }

    static func logRemoteStreamStats(_ stats: ByteRTCRemoteStreamStats) {
        XmaxLogger.debug(
            category: category,
            message: remoteStreamStatsMessage(stats),
            option: .performance
        )
    }

    static func logNetworkQuality(
        localQuality: ByteRTCNetworkQualityStats,
        remoteQualities: [ByteRTCNetworkQualityStats]
    ) {
        XmaxLogger.debug(
            category: category,
            message: networkQualityMessage(
                localQuality: localQuality,
                remoteQualities: remoteQualities
            ),
            option: .performance
        )
    }

    static func logSystemStats(_ stats: ByteRTCSysStats) {
        XmaxLogger.debug(
            category: category,
            message: systemStatsMessage(stats),
            option: .performance
        )
    }

    static func logPerformanceAlarm(
        reason: ByteRTCPerformanceAlarmReason,
        data: ByteRTCSourceWantedData
    ) {
        XmaxLogger.debug(
            category: category,
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
        ├─ 分辨率：\(video.encodedFrameWidth) × \(video.encodedFrameHeight)
        ├─ 发送码率：\(video.sentKBitrate) kbps
        ├─ 采集帧率：\(video.inputFrameRate) fps
        ├─ 编码帧率：\(video.encoderOutputFrameRate) fps
        ├─ 发送帧率：\(video.sentFrameRate) fps
        ├─ 视频丢包率：\(percentage(video.videoLossRate))
        ├─ 网络往返时延：\(video.rtt) ms
        └─ 网络抖动：\(video.jitter) ms
        """
    }

    private static func remoteStreamStatsMessage(
        _ stats: ByteRTCRemoteStreamStats
    ) -> String {
        let video = stats.videoStats
        return """
        远端视频接收 (Remote Video Downlink)
        ├─ 分辨率：\(video.width) × \(video.height)
        ├─ 接收码率：\(video.receivedKBitrate) kbps
        ├─ 解码帧率：\(video.decoderOutputFrameRate) fps
        ├─ 渲染帧率：\(video.renderOutputFrameRate) fps
        ├─ 视频丢包率：\(percentage(video.videoLossRate))
        ├─ 网络往返时延：\(video.rtt) ms
        ├─ 卡顿次数：\(video.stallCount) 次
        ├─ 卡顿时长：\(video.stallDuration) ms
        └─ 端到端时延：\(video.e2eDelay) ms
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
            "\(localBranch) 本地发送（上行）",
            "\(localIndent)├─ 质量：\(networkQualityName(localQuality.txQuality))",
            "\(localIndent)└─ \(networkMetrics(localQuality, includesRtt: true))"
        ]

        for (index, quality) in remoteQualities.enumerated() {
            let isLast = index == remoteQualities.count - 1
            let branch = isLast ? "└─" : "├─"
            let indent = isLast ? "   " : "│  "
            lines.append("\(branch) 远端接收 \(quality.uid)（下行）")
            lines.append(
                "\(indent)├─ 质量：\(networkQualityName(quality.rxQuality))"
            )
            lines.append(
                "\(indent)└─ \(networkMetrics(quality, includesRtt: false))"
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func systemStatsMessage(_ stats: ByteRTCSysStats) -> String {
        let cpu = [
            "应用 \(percentage(stats.cpuAppUsage))",
            "系统 \(percentage(stats.cpuTotalUsage))",
            "\(stats.cpuCores) 核"
        ].joined(separator: "，")
        let memory = [
            "应用 \(String(format: "%.0f", stats.memoryUsage)) MB",
            "应用占用 \(String(format: "%.2f", stats.memoryRatio))%",
            "系统占用 \(String(format: "%.2f", stats.totalMemoryRatio))%"
        ].joined(separator: "，")
        return """
        性能统计 (System Performance Metrics)
        ├─ CPU：\(cpu)
        └─ 内存：\(memory)
        """
    }

    private static func performanceAlarmMessage(
        reason: ByteRTCPerformanceAlarmReason,
        data: ByteRTCSourceWantedData
    ) -> String {
        var lines = ["性能告警 (Performance Alert)"]
        let state = performanceAlarmName(reason)
        if data.width > 0, data.height > 0, data.frameRate > 0 {
            lines.append("├─ 状态：\(state)")
            lines.append(
                "└─ 建议：\(data.width) × \(data.height)，\(data.frameRate) fps"
            )
        } else {
            lines.append("└─ 状态：\(state)")
        }
        return lines.joined(separator: "\n")
    }

    private static func networkMetrics(
        _ quality: ByteRTCNetworkQualityStats,
        includesRtt: Bool
    ) -> String {
        var metrics = ["丢包 \(percentage(quality.lossRatio))"]
        if includesRtt {
            metrics.append("RTT \(quality.rtt) ms")
        }
        metrics.append(
            "带宽 \(String(format: "%.0f", Double(quality.totalBandwidth) / 1_000)) kbps"
        )
        return "指标：\(metrics.joined(separator: "，"))"
    }

    private static func networkQualityName(
        _ quality: ByteRTCNetworkQuality
    ) -> String {
        switch quality {
        case .excellent:
            "极好"
        case .good:
            "良好"
        case .poor:
            "较差"
        case .bad:
            "差"
        case .veryBad:
            "极差"
        case .down:
            "断网"
        default:
            "未知"
        }
    }

    private static func performanceAlarmName(
        _ reason: ByteRTCPerformanceAlarmReason
    ) -> String {
        switch reason {
        case .bandwidthFallback:
            "网络受限"
        case .bandwidthResumed:
            "网络恢复"
        case .fallback:
            "设备性能受限"
        case .resumed:
            "设备性能恢复"
        default:
            "未知"
        }
    }

    private static func percentage<T: BinaryFloatingPoint>(_ value: T) -> String {
        String(format: "%.2f%%", Double(value) * 100)
    }
}
