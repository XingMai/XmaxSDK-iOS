import Foundation

/// 定义传输层向 Core 暴露的统一能力。
protocol TransportControlling: Sendable {

    /// 校验并应用实时视频编码格式。
    func configureVideoEncoding(_ videoFormat: RealtimeVideoFormat) throws

    /// 设置网络质量监听器，传入空值时清除监听器。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    )

    /// 设置设备性能告警监听器，传入空值时清除监听器。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    )

    /// 加入 RTC 房间并发布本地媒体流。
    func connect(
        connection: RealtimeSessionConnection,
        includeLocalAudio: Bool,
        ensureActive: @escaping @Sendable () throws -> Void
    ) async throws

    /// 清理本地发布、远端订阅并离开 RTC 房间。
    func disconnect() async

    /// 更新本地音频发布状态。
    func setLocalAudioEnabled(_ enabled: Bool) throws

    /// 推送本地外部视频帧。
    func pushLocalVideoFrame(_ frame: any VideoFrame) throws

    /// 推送本地外部音频帧。
    func pushLocalAudioFrame(_ frame: AudioFrame) throws

    /// 建立生成任务并发送开始信令。
    func beginGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) async throws -> Task<Void, any Error>

    /// 发送生成条件变更信令。
    func updateGeneration(
        taskID: String,
        conditionVersion: Int,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) async throws

    /// 停止生成任务并清理远端结果流。
    func stopGeneration(taskID: String) async

    /// 发送生成任务的交互轨迹。
    func sendTracks(
        taskID: String,
        points: [RealtimePoint]
    ) async throws
}
