/// 实时业务连接状态。
public enum RealtimeConnectionState: String, CaseIterable, Sendable {

    /// Manager 尚未建立过实时连接。
    case idle = "Idle"

    /// 正在创建 Session、加入 Room 并发布本地流。
    case connecting = "Connecting"

    /// 实时连接已建立，当前没有生成任务。
    case connected = "Connected"

    /// 实时连接已建立且生成任务正在运行。
    case generating = "Generating"

    /// 正在清理生成、Room 和 Session 资源。
    case disconnecting = "Disconnecting"

    /// 实时连接已经主动断开。
    case disconnected = "Disconnected"

    /// 实时连接因错误终止或建立失败。
    case error = "Error"
}

/// 实时业务当前状态快照。
public struct RealtimeState: Equatable, Sendable {

    /// 当前连接生命周期状态。
    public let connectionState: RealtimeConnectionState

    /// 当前或最近一次实时 Session 标识。
    public let sessionID: String?

    /// 当前生成任务标识。
    public let taskID: String?

    /// 创建实时状态快照。
    public init(
        connectionState: RealtimeConnectionState,
        sessionID: String? = nil,
        taskID: String? = nil
    ) {
        self.connectionState = connectionState
        self.sessionID = sessionID
        self.taskID = taskID
    }
}

/// 实时状态监听器。
public typealias RealtimeStateListener = @MainActor @Sendable (
    RealtimeState
) -> Void
