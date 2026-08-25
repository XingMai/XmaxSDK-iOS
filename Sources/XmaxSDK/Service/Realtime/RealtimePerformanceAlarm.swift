/// 实时性能限制状态。
enum RealtimePerformanceStatus: String, CaseIterable, Sendable {
    case limited = "Limited"
    case recovered = "Recovered"
}

/// 实时性能告警信息。
struct RealtimePerformanceAlarm: Equatable, Sendable {
    let status: RealtimePerformanceStatus
    let suggestedVideoFormat: RealtimeVideoFormat?
}

/// 实时性能告警监听器。
typealias RealtimePerformanceAlarmListener = @Sendable (
    RealtimePerformanceAlarm
) -> Void
