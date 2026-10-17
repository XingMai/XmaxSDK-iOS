//
//  StreamControlling.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 定义传输层向 Core 暴露的统一能力。
protocol StreamControlling: Sendable {

    // 自适应质量状态
    /// 当前媒体基准及上下行档位。
    var qualityConfiguration: QualityConfiguration? { get }

    /// 根据媒体基准和模型历史准备上下行档位。
    ///
    /// - Parameters:
    ///   - baseline: 本地媒体原始输出规格，不随调档改变。
    ///   - model: 用于隔离历史档位的模型标识。
    /// - Returns: 本次连接的初始上下行配置。
    func prepareQuality(baseline: RealtimeVideoFormat, model: String) -> QualityConfiguration

    /// 设置内部调档采样回调，不影响公开网络质量监听。
    ///
    /// - Parameter listener: 接收网络质量及单调时钟采样时间；nil 表示移除。
    func setAdaptiveQualityListener(_ listener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?)

    /// 消费当前网络采样并返回候选档位。
    ///
    /// - Parameters:
    ///   - quality: 当前上下行网络质量。
    ///   - sampledAt: 单调时钟的采样时间，单位为秒。
    /// - Returns: 满足连续采样和冷却条件的候选档位。
    func proposeQuality(_ quality: RealtimeNetworkQuality, sampledAt: TimeInterval) -> QualityChange

    /// 提交调档结果，成功时保存历史档位。
    ///
    /// - Parameters:
    ///   - downlink: true 表示下行，false 表示上行。
    ///   - level: 本次尝试的档位，范围为 1...5。
    ///   - success: 配置是否成功应用。
    func completeQuality(downlink: Bool, level: Int, success: Bool)

    /// 清除连续采样窗口。
    func resetQualitySamples()

    // 生成状态
    /// 当前是否存在正在启动或已经运行的生成任务。
    var hasGenerationTask: Bool { get }

    // 远端音频
    /// 当前远端生成音频播放音量。
    var remoteAudioVolume: Float { get }

    /// 设置实时视频编码器配置。
    ///
    /// - Parameter videoFormat: RTC 视频编码使用的宽度、高度和帧率。
    /// - Throws: 视频格式无效或 RTC 编码配置失败时抛出错误。
    func setVideoEncoderConfig(_ videoFormat: RealtimeVideoFormat) throws

    /// 设置视频上行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；未发布或断开连接时收到 nil；传入 nil 清除监听器。
    func setUplinkVideoStatisticsListener(_ listener: UplinkVideoStatisticsListener?)

    /// 设置视频下行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；结果流清理时收到 nil；传入 nil 清除监听器。
    func setDownlinkVideoStatisticsListener(_ listener: DownlinkVideoStatisticsListener?)

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

    /// 建立生成任务、发送开始信令并启动结果流确认等待。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务的唯一标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 生成使用的参考图、提示词等条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否按包含模式保留源比例并填充生成画布。
    /// - Returns: 等待远端结果流发布确认的任务。
    /// - Throws: 任务参数无效、房间未就绪、已有生成任务、信令失败或发送等待超时时抛出错误。
    func beginGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize?,
        context: RealtimeContext,
        faceRestoration: Bool,
        paddingContain: Bool
    ) async throws -> Task<Void, any Error>

    /// 在远端首帧已经可显示后订阅当前生成流的音频。
    ///
    /// - Throws: 当前生成流尚未确认，或 RTC 音量和订阅配置失败时抛出错误。
    func activateRemoteAudio() throws

    /// 发送当前生成任务的条件变更信令。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务的唯一标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 生成使用的参考图、提示词等条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否按包含模式保留源比例并填充生成画布。
    /// - Throws: 房间未就绪、参数无效或信令提交失败时抛出错误。
    func updateGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize?,
        context: RealtimeContext,
        faceRestoration: Bool,
        paddingContain: Bool
    ) async throws

    /// 调整当前生成任务的回传尺寸，不重启生成。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - targetSize: 生成后回传的整数像素尺寸。
    ///   - ensureActive: 发送前确认当前配置操作仍有效。
    /// - Throws: 操作已取消、房间未就绪或信令发送失败时抛出错误。
    func changeTargetSize(
        taskID: String,
        targetSize: CGSize,
        ensureActive: @escaping @Sendable () throws -> Void
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
