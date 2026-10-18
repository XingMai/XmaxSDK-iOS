//
//  RtcManaging.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 定义 RTC 引擎、房间、媒体传输和远端帧输出能力。
protocol RtcManaging: Sendable {

    /// 获取独占的 RTC 引擎租约并完成初始化。
    ///
    /// - Throws: 等待租约被取消或 RTC 引擎初始化失败时抛出错误。
    func initialize() async throws

    /// 销毁 RTC 引擎并释放资源。
    func destroy() async

    /// 应用上传视频的编码配置。
    ///
    /// - Parameter configuration: 尺寸、帧率、码率和编码偏好。
    /// - Throws: 厂商引擎拒绝配置时抛出错误。
    func configureVideoEncoding(
        _ configuration: VideoEncodingConfiguration
    ) throws

    /// 切换至麦克风输入并开始采集。
    ///
    /// - Throws: 音频源切换或采集失败时抛出错误。
    func startAudioCapture() throws

    /// 停止麦克风采集。
    ///
    /// - Throws: 厂商引擎停止采集失败时抛出错误。
    func stopAudioCapture() throws

    /// 启用外部视频输入。
    ///
    /// - Throws: 视频源配置失败时抛出错误。
    func useExternalVideoSource() throws

    /// 启用外部 PCM 输入。
    ///
    /// - Throws: 外部音频轨创建失败时抛出错误。
    func startExternalAudioSource() throws

    /// 停止外部 PCM 输入并释放音频轨。
    ///
    /// - Throws: 音频轨释放失败时抛出错误。
    func stopExternalAudioSource() throws

    /// 更新上传视频镜像。
    ///
    /// - Parameter position: 当前摄像头位置。
    /// - Throws: 编码镜像配置失败时抛出错误。
    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws

    /// 推送外部视频帧。
    ///
    /// - Parameter frame: SDK 中性视频帧。
    /// - Throws: 帧格式或数据无效时抛出错误。
    func pushExternalVideoFrame(_ frame: VideoFrame) throws

    /// 推送外部音频帧。
    ///
    /// - Parameter frame: 带时间戳的 10 ms PCM 数据。
    /// - Throws: 帧格式或数据无效时抛出错误。
    func pushExternalAudioFrame(_ frame: AudioFrame) throws

    /// 加入 RTC 房间并等待连接完成。
    ///
    /// - Parameter configuration: 房间、用户标识及令牌配置。
    /// - Throws: 引擎不可用、进房失败、连接超时或调用取消时抛出错误。
    func joinRoom(
        configuration: RoomJoinConfiguration
    ) async throws

    /// 离开当前 RTC 房间。
    func leaveRoom() async

    /// 发布本地视频流。
    ///
    /// - Throws: 房间不可用或视频发布失败时抛出错误。
    func publishLocalVideo() throws

    /// 停止发布本地视频流。
    ///
    /// - Throws: 房间不可用或停止视频发布失败时抛出错误。
    func unpublishLocalVideo() throws

    /// 发布本地音频流。
    ///
    /// - Throws: 房间不可用或音频发布失败时抛出错误。
    func publishLocalAudio() throws

    /// 停止发布本地音频流。
    ///
    /// - Throws: 房间不可用或停止音频发布失败时抛出错误。
    func unpublishLocalAudio() throws

    /// 设置指定远端用户的视频订阅状态。
    ///
    /// - Parameters:
    ///   - userID: 远端 RTC 用户标识。
    ///   - subscribe: 是否订阅视频流。
    /// - Throws: 房间不可用、用户映射或订阅配置失败时抛出错误。
    func subscribeRemoteVideo(
        userID: String,
        subscribe: Bool
    ) throws

    /// 设置指定远端用户的音频订阅状态。
    ///
    /// - Parameters:
    ///   - userID: 远端 RTC 用户标识。
    ///   - subscribe: 是否订阅音频流。
    /// - Throws: 房间不可用、用户映射或订阅配置失败时抛出错误。
    func subscribeRemoteAudio(
        userID: String,
        subscribe: Bool
    ) throws

    /// 设置指定远端用户的音频播放音量。
    ///
    /// - Parameters:
    ///   - volume: 播放音量，范围为 0 到 100。
    ///   - userID: 远端 RTC 用户标识。
    /// - Throws: 房间不可用或音量设置失败时抛出错误。
    func setRemoteAudioVolume(
        _ volume: Int,
        for userID: String
    ) throws

    /// 设置指定远端流的解码帧监听器。
    ///
    /// - Parameters:
    ///   - listener: 解码帧回调；传入 `nil` 清除监听。
    ///   - stream: 需要监听的远端流。
    /// - Throws: 房间不可用或帧监听设置失败时抛出错误。
    func setRemoteVideoFrameListener(
        _ listener: RtcRemoteVideoFrameListener?,
        for stream: RemoteStream
    ) throws

    /// 向当前 RTC 房间发送消息。
    ///
    /// - Parameters:
    ///   - message: 完整 JSON 信令。
    ///   - reportFailure: 异步发送失败时是否上报房间故障。
    ///   - replacingPendingMessage: 合并键；同键且尚未发送的信令仅保留最新内容。
    /// - Returns: 本条信令的发送任务，可用于等待独立的发送结果。
    /// - Throws: 入队失败时抛出错误。
    @discardableResult
    func sendRoomMessage(
        _ message: String,
        reportFailure: Bool,
        replacingPendingMessage key: String?
    ) throws -> Task<Void, any Error>

    /// 丢弃尚未开始发送的可合并信令。
    ///
    /// - Parameter key: 需要清理的合并键；`nil` 清理所有可合并信令。
    func discardPendingMessages(key: String?)

    /// 等待已入队的房间信令发送完成。
    ///
    /// - Throws: 房间不可用、消息发送失败或等待取消时抛出错误。
    func awaitPendingMessages() async throws

    /// 设置 RTC 连接及媒体事件监听器。
    ///
    /// - Parameter listener: 事件监听器；传入 `nil` 清除监听。
    func setEventListener(_ listener: (any RtcEventListener)?)

    /// 设置 RTC 网络及媒体质量监听器。
    ///
    /// - Parameter listener: 质量监听器；传入 `nil` 清除监听。
    func setQualityListener(_ listener: (any RtcQualityListener)?)
}

extension RtcManaging {
    /// 将房间信令入队，并启用异步发送失败通知。
    ///
    /// - Parameters:
    ///   - message: 完整 JSON 信令。
    ///   - reportFailure: 异步发送失败时是否通知房间故障。
    /// - Returns: 本条信令的发送任务。
    /// - Throws: 信令无法入队时抛出错误。
    @discardableResult
    func sendRoomMessage(_ message: String, reportFailure: Bool = true) throws -> Task<Void, any Error> {
        try sendRoomMessage(message, reportFailure: reportFailure, replacingPendingMessage: nil)
    }
}
