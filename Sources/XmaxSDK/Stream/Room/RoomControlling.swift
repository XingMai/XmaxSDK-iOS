/// 定义 RTC 房间生命周期和业务信令发送能力。
protocol RoomControlling: Actor {

    /// 加入实时房间，并在异步边界前后确认连接操作仍然有效。
    func join(
        connection: RealtimeSessionConnection,
        ensureActive: @escaping @Sendable () throws -> Void
    ) async throws

    /// 停止房间心跳并离开当前 RTC 房间。
    func leave() async

    /// 发送生成开始信令。
    func startGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) throws

    /// 发送生成条件变更信令。
    func changeGenerationCondition(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) throws

    /// 尝试发送生成停止信令，未进房或任务为空时忽略。
    ///
    /// - Throws: RTC 停止信令发送失败时抛出错误。
    func stopGeneration(taskID: String) throws

    /// 发送生成任务的交互轨迹。
    func sendTracks(
        taskID: String,
        points: [RealtimePoint]
    ) throws
}
