import Foundation

/// 定义传输层向 Core 暴露的统一能力。
protocol StreamControlling: Sendable {

    /// 当前是否存在正在启动或已经运行的生成任务。
    var hasGenerationTask: Bool { get }

    /// 设置实时视频编码器配置。
    ///
    /// - Parameter videoFormat: RTC 视频编码使用的宽度、高度和帧率。
    /// - Throws: 视频格式无效或 RTC 编码配置失败时抛出错误。
    func setVideoEncoderConfig(_ videoFormat: RealtimeVideoFormat) throws

    /// 设置网络质量监听器，传入空值时清除监听器。
    ///
    /// - Parameter listener: 接收上行和下行网络质量事件的监听器；
    ///   传入空值时清除现有监听器。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    )

    /// 设置设备性能告警监听器，传入空值时清除监听器。
    ///
    /// - Parameter listener: 接收设备性能受限与恢复事件的监听器；
    ///   传入空值时清除现有监听器。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    )

    /// 设置远端生成音频播放音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 `0...1` 的音量。
    /// - Throws: RTC 音量配置失败时抛出错误。
    func setRemoteAudioVolume(_ volume: Float) throws

    /// 加入 RTC 房间并发布本地媒体流。
    ///
    /// - Parameters:
    ///   - connection: RTC 房间、用户、Token 和目标机器人信息。
    ///   - includeLocalAudio: 是否随本地视频一起发布本地音频。
    ///   - ensureActive: 在异步边界校验当前连接操作仍然有效的回调；
    ///     无效时应抛出取消错误。
    /// - Throws: 连接已取消，或 RTC 进房、房间配置与本地流发布失败时
    ///   抛出错误。
    func connect(
        connection: RealtimeSessionConnection,
        includeLocalAudio: Bool,
        ensureActive: @escaping @Sendable () throws -> Void
    ) async throws

    /// 清理生成状态、本地发布和远端订阅，并离开当前 RTC 房间；
    /// 没有活动房间时安全返回。
    func disconnect() async

    /// 更新本地音频发布状态。
    ///
    /// - Parameter enabled: `true` 表示发布本地音频，`false` 表示取消发布。
    /// - Throws: 当前房间或本地视频尚未就绪，或 RTC 发布状态更新失败时
    ///   抛出错误。
    func setLocalAudioEnabled(_ enabled: Bool) throws

    /// 在生成任务活动期间推送本地外部视频帧；无生成任务时忽略。
    ///
    /// - Parameter frame: 已准备好交给 RTC 的本地视频帧。
    /// - Throws: RTC 资源尚未就绪或视频帧转换失败时抛出错误。
    func pushLocalVideoFrame(_ frame: VideoFrame) throws

    /// 推送本地外部音频帧。
    ///
    /// - Parameter frame: 已准备好交给 RTC 的 PCM 音频帧；
    ///   本地音频尚未发布时忽略。
    /// - Throws: RTC 资源尚未就绪或音频帧转换失败时抛出错误。
    func pushLocalAudioFrame(_ frame: AudioFrame) throws

    /// 建立生成任务并发送开始信令。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务的唯一标识，同时用于 SEI 匹配。
    ///   - videoFormat: 当前本地媒体使用的视频格式。
    ///   - context: 当前生成任务使用的条件上下文。
    /// - Returns: 等待匹配远端结果流确认的任务。
    /// - Throws: 任务标识无效、RTC 房间未就绪、已有生成任务，或开始信令
    ///   发送失败时抛出错误。
    func beginGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) async throws -> Task<Void, any Error>

    /// 在远端首帧已经可显示后订阅当前生成流的音频。
    ///
    /// - Throws: 当前生成流尚未确认，或 RTC 音量和订阅配置失败时抛出错误。
    func activateRemoteAudio() throws

    /// 发送生成条件变更信令。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务的唯一标识。
    ///   - videoFormat: 当前本地媒体使用的视频格式。
    ///   - context: 更新后的生成条件上下文。
    /// - Throws: RTC 房间未就绪、参数无效或条件变更信令发送失败时
    ///   抛出错误。
    func updateGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) async throws

    /// 停止生成任务并清理远端结果流。
    ///
    /// - Parameter taskID: 需要停止的生成任务标识；传入空字符串时停止
    ///   当前任务。
    /// - Throws: RTC 停止信令发送失败时抛出错误。
    func stopGeneration(taskID: String) async throws

    /// 发送生成任务的交互轨迹。
    ///
    /// - Parameters:
    ///   - taskID: 接收交互轨迹的生成任务标识。
    ///   - points: 需要发送的轨迹点；空数组会被忽略。
    /// - Throws: RTC 房间未就绪、任务标识无效或轨迹信令发送失败时
    ///   抛出错误。
    func sendTracks(
        taskID: String,
        points: [RealtimePoint]
    ) async throws
}
