//
//  RtcStatsLogger.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 将声网 RTC 运行统计输出为统一的 Xmax 调试日志。
enum RtcStatsLogger {

    /// 在性能日志启用时输出视频上行指标。
    ///
    /// - Parameter video: 当前上行视频统计。
    static func logUplinkVideoStatistics(
        _ video: UplinkVideoStatistics
    ) {
        XmaxLogger.rtc.debug(message: uplinkVideoStatisticsMessage(video), option: .performance)
    }

    /// 格式化上行统计日志。
    ///
    /// - Parameter video: 当前上行视频统计。
    /// - Returns: 包含本地化字段名称的上行日志正文。
    static func uplinkVideoStatisticsMessage(
        _ video: UplinkVideoStatistics
    ) -> String {
        """
        视频上行统计 (Video Uplink Statistics)
        ├─ \(XmaxLogger.localized("分辨率：", "Resolution: "))\(resolution(video.width, video.height))
        ├─ \(XmaxLogger.localized("发送码率：", "Send Bitrate: "))\(value(video.bitrateKbps, unit: "kbps"))
        ├─ \(XmaxLogger.localized("采集帧率：", "Capture Frame Rate: "))\(value(video.captureFrameRate, unit: "fps"))
        ├─ \(XmaxLogger.localized("编码帧率：", "Encode Frame Rate: "))\(value(video.encodeFrameRate, unit: "fps"))
        ├─ \(XmaxLogger.localized("发送帧率：", "Send Frame Rate: "))\(value(video.sendFrameRate, unit: "fps"))
        └─ \(XmaxLogger.localized("视频丢包率：", "Video Packet Loss: "))\(value(video.packetLossPercent, unit: "%"))
        """
    }

    /// 在性能日志启用时输出视频下行指标。
    ///
    /// - Parameter video: 当前下行视频统计。
    static func logDownlinkVideoStatistics(
        _ video: DownlinkVideoStatistics
    ) {
        XmaxLogger.rtc.debug(message: downlinkVideoStatisticsMessage(video), option: .performance)
    }

    /// 格式化下行统计日志。
    ///
    /// - Parameter video: 当前下行视频统计。
    /// - Returns: 包含本地化字段名称的下行日志正文。
    static func downlinkVideoStatisticsMessage(
        _ video: DownlinkVideoStatistics
    ) -> String {
        """
        视频下行统计 (Video Downlink Statistics)
        ├─ \(XmaxLogger.localized("分辨率：", "Resolution: "))\(resolution(video.width, video.height))
        ├─ \(XmaxLogger.localized("接收码率：", "Receive Bitrate: "))\(value(video.bitrateKbps, unit: "kbps"))
        ├─ \(XmaxLogger.localized("解码帧率：", "Decode Frame Rate: "))\(value(video.decodeFrameRate, unit: "fps"))
        ├─ \(XmaxLogger.localized("渲染帧率：", "Render Frame Rate: "))\(value(video.renderFrameRate, unit: "fps"))
        ├─ \(XmaxLogger.localized("视频丢包率：", "Video Packet Loss: "))\(value(video.packetLossPercent, unit: "%"))
        └─ \(XmaxLogger.localized("端到端时延：", "End-to-End Delay: "))\(value(video.endToEndDelayMs, unit: "ms"))
        """
    }

    /// 格式化可用的视频分辨率。
    ///
    /// - Parameters:
    ///   - width: 像素宽度；不可用时为 `nil`。
    ///   - height: 像素高度；不可用时为 `nil`。
    /// - Returns: 宽高文本；任一值不可用时返回占位符。
    private static func resolution(
        _ width: Int?,
        _ height: Int?
    ) -> String {
        guard let width, let height else { return "—" }
        return "\(width) × \(height)"
    }

    /// 为可用统计值追加单位。
    ///
    /// - Parameters:
    ///   - number: 统计值；不可用时为 `nil`。
    ///   - unit: 统计值的单位。
    /// - Returns: 带单位的数值文本或不可用占位符。
    private static func value(
        _ number: Int?,
        unit: String
    ) -> String {
        number.map { "\($0) \(unit)" } ?? "—"
    }
}
