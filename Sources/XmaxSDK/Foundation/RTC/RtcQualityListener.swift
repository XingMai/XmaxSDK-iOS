//
//  RtcQualityListener.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

    /// 接收本地视频上行统计。
    ///
    /// - Parameter statistics: 当前统计周期的上行指标。
    @MainActor
    func onUplinkVideoStatistics(_ statistics: UplinkVideoStatistics)

    /// 接收远端视频下行统计。
    ///
    /// - Parameter statistics: 当前统计周期的下行指标。
    @MainActor
    func onDownlinkVideoStatistics(_ statistics: DownlinkVideoStatistics)

    /// 接收上下行实时网络质量。
    ///
    /// - Parameters:
    ///   - uplink: 本地发送方向的网络质量。
    ///   - downlink: 远端接收方向的网络质量。
    @MainActor
    func onNetworkQuality(
        uplink: RtcQualityLevel,
        downlink: RtcQualityLevel
    )

    /// 接收性能受限或恢复事件。
    ///
    /// - Parameters:
    ///   - limited: 当前是否受性能限制。
    ///   - suggestedWidth: 建议的视频宽度，单位为像素。
    ///   - suggestedHeight: 建议的视频高度，单位为像素。
    ///   - suggestedFrameRate: 建议的视频帧率，单位为 fps。
    @MainActor
    func onPerformanceAlarm(
        limited: Bool,
        suggestedWidth: Int,
        suggestedHeight: Int,
        suggestedFrameRate: Int
    )
}
