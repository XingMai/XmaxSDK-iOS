/// RTC 网络质量等级。
public enum RealtimeNetworkQualityLevel: String, CaseIterable, Sendable {

    /// RTC 尚未提供有效质量数据。
    case unknown = "Unknown"

    /// 网络质量优秀。
    case excellent = "Excellent"

    /// 网络质量良好。
    case good = "Good"

    /// 网络质量较差，实时体验可能开始受影响。
    case poor = "Poor"

    /// 网络质量很差，实时体验明显受影响。
    case bad = "Bad"

    /// 网络质量极差，媒体传输可能严重中断。
    case veryBad = "VeryBad"

    /// 网络连接已经中断。
    case down = "Down"
}

/// 实时会话的上下行网络质量。
public struct RealtimeNetworkQuality: Equatable, Sendable {

    /// 本地向 RTC 房间发送媒体的网络质量。
    public let uplink: RealtimeNetworkQualityLevel

    /// 本地从 RTC 房间接收媒体的网络质量。
    public let downlink: RealtimeNetworkQualityLevel

    /// 创建上下行网络质量信息。
    public init(
        uplink: RealtimeNetworkQualityLevel,
        downlink: RealtimeNetworkQualityLevel
    ) {
        self.uplink = uplink
        self.downlink = downlink
    }
}

/// 实时网络质量监听器。
public typealias RealtimeNetworkQualityListener = @MainActor @Sendable (
    RealtimeNetworkQuality
) -> Void
