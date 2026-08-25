import Foundation
@preconcurrency import VolcEngineRTC

/// 将火山 RTC 运行统计输出为统一的 Xmax 调试日志。
enum RtcStatsLogger {

    // 日志配置
    private static let category = "RTC"

    static func logLocalStreamStats(_ stats: ByteRTCLocalStreamStats) {
        let video = stats.videoStats

        XmaxLogger.debug(
            """
            本地视频发送
            ├─ 分辨率：\(video.encodedFrameWidth) × \(video.encodedFrameHeight)
            ├─ 码率：\(video.sentKBitrate) kbps
            ├─ 帧率：采集 \(video.inputFrameRate) fps，编码 \(video.encoderOutputFrameRate) fps，发送 \(video.sentFrameRate) fps
            └─ 网络：丢包 \(percentage(video.videoLossRate))，RTT \(video.rtt) ms，抖动 \(video.jitter) ms
            """,
            category: category
        )
    }

    static func logRemoteStreamStats(_ stats: ByteRTCRemoteStreamStats) {
        let video = stats.videoStats

        XmaxLogger.debug(
            """
            远端视频接收
            ├─ 分辨率：\(video.width) × \(video.height)
            ├─ 码率：\(video.receivedKBitrate) kbps
            ├─ 帧率：解码 \(video.decoderOutputFrameRate) fps，渲染 \(video.renderOutputFrameRate) fps
            ├─ 网络：丢包 \(percentage(video.videoLossRate))，RTT \(video.rtt) ms
            ├─ 卡顿：\(video.stallCount) 次，\(video.stallDuration) ms
            └─ 时延：端到端 \(video.e2eDelay) ms
            """,
            category: category
        )
    }

    static func logNetworkQuality(
        localQuality: ByteRTCNetworkQualityStats,
        remoteQualities: [ByteRTCNetworkQualityStats]
    ) {
        let hasRemoteQuality = !remoteQualities.isEmpty
        let localBranch = hasRemoteQuality ? "├─" : "└─"
        let localIndent = hasRemoteQuality ? "│  " : "   "
        var lines = [
            "网络质量",
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

        XmaxLogger.debug(lines.joined(separator: "\n"), category: category)
    }

    static func logSystemStats(_ stats: ByteRTCSysStats) {
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

        XmaxLogger.debug(
            """
            性能统计
            ├─ CPU：\(cpu)
            └─ 内存：\(memory)
            """,
            category: category
        )
    }

    static func logPerformanceAlarm(
        reason: ByteRTCPerformanceAlarmReason,
        data: ByteRTCSourceWantedData
    ) {
        var lines = ["性能告警"]
        let state = performanceAlarmName(reason)
        if data.width > 0, data.height > 0, data.frameRate > 0 {
            lines.append("├─ 状态：\(state)")
            lines.append(
                "└─ 建议：\(data.width) × \(data.height)，\(data.frameRate) fps"
            )
        } else {
            lines.append("└─ 状态：\(state)")
        }

        XmaxLogger.debug(lines.joined(separator: "\n"), category: category)
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
