/// 定义实时会话 API 与心跳生命周期能力。
protocol RealtimeSessionServicing: Sendable {

    /// 创建实时会话并返回 RTC 连接信息。
    func createSession(model: RealtimeModel) async throws -> RealtimeSession

    /// 启动指定会话的周期心跳。
    func startHeartbeat(
        sessionID: String,
        onFailure: @escaping RealtimeSessionHeartbeatFailureHandler
    )

    /// 停止当前心跳；已经失效的迟到结果不会再触发失败回调。
    func stopHeartbeat()

    /// 关闭指定实时会话。
    func closeSession(sessionID: String) async throws
}
