/// 实时业务连接状态。
enum RealtimeConnectionState: String, CaseIterable, Sendable {
    case idle = "Idle"
    case connecting = "Connecting"
    case connected = "Connected"
    case generating = "Generating"
    case disconnecting = "Disconnecting"
    case disconnected = "Disconnected"
    case error = "Error"
}

/// 实时业务当前状态快照。
struct RealtimeState: Equatable, Sendable {
    let connectionState: RealtimeConnectionState
    let sessionID: String?
    let taskID: String?
}

/// 实时状态监听器。
typealias RealtimeStateListener = @Sendable (RealtimeState) -> Void
