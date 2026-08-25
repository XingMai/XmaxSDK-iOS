/// 定义 RTC 媒体流发布、推帧和远端生成流匹配能力。
protocol StreamControlling: Sendable {

    /// 配置当前房间及目标远端用户。
    func configureRoom(
        roomID: String,
        botName: String?
    ) throws

    /// 发布本地视频，并按需发布本地音频。
    func publishLocalStream(includeAudio: Bool) throws

    /// 更新本地音频发布状态。
    func setLocalAudioEnabled(_ enabled: Bool) throws

    /// 推送本地外部视频帧，并附带当前任务标识。
    func pushLocalVideoFrame(_ frame: any VideoFrame) throws

    /// 在本地音频已经发布时推送外部音频帧。
    func pushLocalAudioFrame(_ frame: AudioFrame) throws

    /// 同步建立生成任务并返回远端结果确认任务。
    func beginGeneration(
        taskID: String
    ) throws -> Task<Void, any Error>

    /// 停止指定生成任务并清理远端结果流。
    @MainActor
    func stopGeneration(
        taskID: String,
        reason: String
    ) -> String

    /// 清理当前房间中的本地发布与远端订阅状态。
    @MainActor
    func resetRoom()
}

extension StreamControlling {
    @MainActor
    func stopGeneration(taskID: String = "") -> String {
        stopGeneration(
            taskID: taskID,
            reason: "Realtime generation start cancelled"
        )
    }
}
