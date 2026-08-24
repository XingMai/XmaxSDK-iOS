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
@MainActor
protocol RtcQualityListener: AnyObject {

    /// 处理本地发送和远端接收的实时网络质量。
    func onNetworkQuality(
        uplink: RtcQualityLevel,
        downlink: RtcQualityLevel
    )

    /// 处理实时性能受限或恢复事件。
    func onPerformanceAlarm(
        limited: Bool,
        suggestedWidth: Int,
        suggestedHeight: Int,
        suggestedFrameRate: Int
    )
}
