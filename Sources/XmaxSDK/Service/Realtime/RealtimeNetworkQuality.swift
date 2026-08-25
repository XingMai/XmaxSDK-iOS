/// RTC 网络质量等级。
enum RealtimeNetworkQualityLevel: String, CaseIterable, Sendable {
    case unknown = "Unknown"
    case excellent = "Excellent"
    case good = "Good"
    case poor = "Poor"
    case bad = "Bad"
    case veryBad = "VeryBad"
    case down = "Down"
}

/// 实时会话的上下行网络质量。
struct RealtimeNetworkQuality: Equatable, Sendable {
    let uplink: RealtimeNetworkQualityLevel
    let downlink: RealtimeNetworkQualityLevel
}

/// 实时网络质量监听器。
typealias RealtimeNetworkQualityListener = @Sendable (
    RealtimeNetworkQuality
) -> Void
