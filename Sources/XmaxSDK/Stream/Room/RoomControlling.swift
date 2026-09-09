import CoreGraphics

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
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 模型生成使用的视频规格。
    ///   - targetSize: 服务端生成后的回传尺寸；为 `nil` 时保持生成尺寸。
    ///   - context: 当前生成条件。
    /// - Throws: 房间未就绪、参数无效或信令发送失败时抛出错误。
    func startGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize?,
        context: RealtimeContext
    ) throws

    /// 发送生成条件变更信令。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 模型生成使用的视频规格。
    ///   - targetSize: 当前连接的回传尺寸；为 `nil` 时保持生成尺寸。
    ///   - context: 更新后的生成条件。
    /// - Throws: 房间未就绪、参数无效或信令发送失败时抛出错误。
    func changeGenerationCondition(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize?,
        context: RealtimeContext
    ) throws

    /// 调整当前生成任务的回传尺寸。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - targetSize: 生成后回传的整数像素尺寸。
    ///   - ensureActive: 发送前确认当前配置操作仍有效。
    /// - Throws: 操作已取消、房间未就绪或信令发送失败时抛出错误。
    func changeTargetSize(
        taskID: String,
        targetSize: CGSize,
        ensureActive: @Sendable () throws -> Void
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
