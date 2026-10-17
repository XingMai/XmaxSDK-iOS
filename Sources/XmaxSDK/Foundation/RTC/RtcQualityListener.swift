//
//  RtcQualityListener.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 中性的 RTC 网络质量等级。
enum RtcQualityLevel: Int, CaseIterable, Sendable {
    case unknown
    case excellent
    case good
    case poor
    case bad
    case veryBad
    case down
}

/// 接收 RTC 网络质量和性能回退事件。
protocol RtcQualityListener: AnyObject {

    /// 处理实际视频上行统计。
    @MainActor
    func onUplinkVideoStatistics(_ statistics: UplinkVideoStatistics)

    /// 处理实际视频下行统计。
    @MainActor
    func onDownlinkVideoStatistics(_ statistics: DownlinkVideoStatistics)

    /// 处理本地发送和远端接收的实时网络质量。
    @MainActor
    func onNetworkQuality(
        uplink: RtcQualityLevel,
        downlink: RtcQualityLevel
    )

    /// 处理实时性能受限或恢复事件。
    @MainActor
    func onPerformanceAlarm(
        limited: Bool,
        suggestedWidth: Int,
        suggestedHeight: Int,
        suggestedFrameRate: Int
    )
}
