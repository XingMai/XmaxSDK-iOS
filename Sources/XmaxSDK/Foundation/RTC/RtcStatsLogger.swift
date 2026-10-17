//
//  RtcStatsLogger.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 将声网 RTC 运行统计输出为统一的 Xmax 调试日志。
enum RtcStatsLogger {
    static func logUplinkVideoStatistics(_ video: UplinkVideoStatistics) {
        XmaxLogger.rtc.debug(message: uplinkVideoStatisticsMessage(video), option: .performance)
    }

    static func uplinkVideoStatisticsMessage(_ video: UplinkVideoStatistics) -> String {
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

    static func logDownlinkVideoStatistics(_ video: DownlinkVideoStatistics) {
        XmaxLogger.rtc.debug(message: downlinkVideoStatisticsMessage(video), option: .performance)
    }

    static func downlinkVideoStatisticsMessage(_ video: DownlinkVideoStatistics) -> String {
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

    private static func resolution(_ width: Int?, _ height: Int?) -> String {
        guard let width, let height else { return "—" }
        return "\(width) × \(height)"
    }

    private static func value(_ number: Int?, unit: String) -> String {
        number.map { "\($0) \(unit)" } ?? "—"
    }
}
