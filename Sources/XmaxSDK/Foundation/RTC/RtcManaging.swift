//
//  RtcManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 定义 RTC 引擎、房间、媒体传输和远端帧输出能力。
protocol RtcManaging: Sendable {

    /// 初始化 RTC 引擎。
    func initialize() async throws

    /// 销毁 RTC 引擎并释放资源。
    func destroy() async

    /// 应用视频编码配置。
    func configureVideoEncoding(
        _ configuration: VideoEncodingConfiguration
    ) throws

    /// 切换到 RTC 内部音频源并启动麦克风采集。
    ///
    /// - Throws: 引擎未初始化、音频源切换或采集启动失败时抛出错误。
    func startAudioCapture() throws

    /// 停止 RTC 内部麦克风采集。
    ///
    /// - Throws: RTC 音频采集停止失败时抛出错误。
    func stopAudioCapture() throws

    /// 将本地视频源切换为外部视频帧。
    func useExternalVideoSource() throws

    /// 启动 RTC 外部音频源。
    func startExternalAudioSource() throws

    /// 停止 RTC 外部音频源。
    func stopExternalAudioSource() throws

    /// 根据相机位置更新本地视频镜像配置。
    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws

    /// 推送一帧外部视频数据。
    func pushExternalVideoFrame(_ frame: VideoFrame) throws

    /// 推送一帧 10 ms PCM 外部音频数据。
    func pushExternalAudioFrame(_ frame: AudioFrame) throws

    /// 加入 RTC 房间。
    func joinRoom(
        configuration: RoomJoinConfiguration
    ) async throws

    /// 离开当前 RTC 房间。
    func leaveRoom() async

    /// 发布本地视频流。
    func publishLocalVideo() throws

    /// 停止发布本地视频流。
    func unpublishLocalVideo() throws

    /// 发布本地音频流。
    func publishLocalAudio() throws

    /// 停止发布本地音频流。
    func unpublishLocalAudio() throws

    /// 更新远端视频流订阅状态。
    func subscribeRemoteVideo(
        userID: String,
        subscribe: Bool
    ) throws

    /// 更新远端音频流订阅状态。
    func subscribeRemoteAudio(
        userID: String,
        subscribe: Bool
    ) throws

    /// 设置指定远端用户的音频播放音量。
    func setRemoteAudioVolume(
        _ volume: Int,
        for userID: String
    ) throws

    /// 设置指定远端流的解码视频帧监听器，传入空值时停止帧回调。
    func setRemoteVideoFrameListener(
        _ listener: RtcRemoteVideoFrameListener?,
        for stream: RemoteStream
    ) throws

    /// 向当前 RTC 房间发送消息。
    ///
    /// - Parameters:
    ///   - message: 完整 JSON 信令。
    ///   - reportFailure: 异步发送失败时是否上报房间故障。
    /// - Returns: 本条信令的发送任务，可用于等待独立的发送结果。
    /// - Throws: 入队失败时抛出错误。
    @discardableResult
    func sendRoomMessage(_ message: String, reportFailure: Bool) throws -> Task<Void, any Error>

    /// 等待当前已入队的房间信令发送完成。
    func awaitPendingMessages() async throws

    /// 设置 RTC 事件监听器，传入空值时清除监听器。
    func setEventListener(_ listener: (any RtcEventListener)?)

    /// 设置 RTC 质量事件监听器，传入空值时清除监听器。
    func setQualityListener(_ listener: (any RtcQualityListener)?)
}

extension RtcManaging {
    func sendRoomMessage(_ message: String) throws {
        try sendRoomMessage(message, reportFailure: true)
    }
}
