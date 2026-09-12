/// 实时业务连接状态。
public enum RealtimeConnectionState: String, CaseIterable, Sendable {

    /// 没有可用的本地媒体流。
    case idle = "Idle"

    /// 正在准备本地媒体流；摄像头还需等待有效帧和预览视图绑定。
    case preparing = "Preparing"

    /// 本地媒体流已就绪，可以预览、连接和生成。
    case ready = "Ready"

    /// 正在创建 Session、加入 Room 并发布本地流。
    case connecting = "Connecting"

    /// 实时连接已建立，当前没有生成任务。
    case connected = "Connected"

    /// 实时连接已建立且生成任务正在运行。
    case generating = "Generating"

    /// 正在清理生成、Room 和 Session 资源。
    case disconnecting = "Disconnecting"

}

/// 进入当前实时状态的原因。
public enum RealtimeReason: Equatable, Sendable {

    /// 主动停止或正常释放资源。
    case normal

    /// 显示方向变化，需要重新配置生成。
    case orientationChanged

    /// 操作或运行异常导致当前流程结束。
    case failure(XmaxError)
}

/// 实时业务当前状态快照。
public struct RealtimeState: Equatable, Sendable {

    /// 当前连接生命周期状态。
    public let connectionState: RealtimeConnectionState

    /// 当前或最近一次实时 Session 标识。
    public let sessionID: String?

    /// 当前生成任务标识。
    public let taskID: String?

    /// 进入当前状态的原因；正常开始新的操作时清空。
    public let reason: RealtimeReason?

    /// 创建实时状态快照。
    ///
    /// - Parameters:
    ///   - connectionState: 当前连接生命周期状态。
    ///   - sessionID: 当前或最近一次实时 Session 标识。
    ///   - taskID: 当前生成任务标识。
    ///   - reason: 状态变化原因，默认无。
    public init(
        connectionState: RealtimeConnectionState,
        sessionID: String? = nil,
        taskID: String? = nil,
        reason: RealtimeReason? = nil
    ) {
        self.connectionState = connectionState
        self.sessionID = sessionID
        self.taskID = taskID
        self.reason = reason
    }
}

/// 实时状态监听器。
public typealias RealtimeStateListener = @MainActor @Sendable (
    RealtimeState
) -> Void
