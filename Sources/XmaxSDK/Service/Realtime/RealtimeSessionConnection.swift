/// 实时会话对应的 RTC 连接参数。
struct RealtimeSessionConnection: Equatable, Sendable {
    let roomID: String
    let userID: String
    let token: String
    let botName: String?
}

/// 实时会话心跳失败回调。
typealias RealtimeSessionHeartbeatFailureHandler = @Sendable (
    _ sessionID: String,
    _ error: XmaxError
) async -> Void
