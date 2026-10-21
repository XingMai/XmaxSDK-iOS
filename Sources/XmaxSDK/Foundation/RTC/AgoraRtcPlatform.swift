//
//  AgoraRtcPlatform.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AgoraRtcKit
import Foundation

/// 将中性引擎操作转换为声网调用。
final class AgoraRtcPlatform: RtcPlatform, @unchecked Sendable {

    /// 已初始化的声网引擎。
    let engine: AgoraRtcEngineKit

    /// 串行保护引擎配置与房间操作。
    let lock = NSRecursiveLock()

    /// 当前平台实例创建的 RTC 房间。
    private weak var room: AgoraRtcRoom?

    /// 复用外部视频帧的声网适配结果。
    private let videoFrameCache = RtcVideoFrameCache()

    /// 最近应用的视频编码配置。
    private var videoConfiguration: VideoEncodingConfiguration?

    /// 当前本地视频编码镜像模式。
    private var videoMirrorMode = AgoraVideoMirrorMode.disabled

    /// 当前外部音频轨标识。
    private(set) var audioTrackID: Int?

    /// 包装声网引擎以提供 SDK 平台接口。
    private init(
        engine: AgoraRtcEngineKit
    ) {
        self.engine = engine
    }

    /// 创建声网引擎，并禁用默认的摄像头和麦克风采集。
    ///
    /// - Parameter appID: 声网应用标识。
    /// - Returns: 初始化成功的平台适配器；配置失败时返回 `nil`。
    static func create(
        appID: String
    ) -> (any RtcPlatform)? {
        let configuration = AgoraRtcEngineConfig()
        configuration.appId = appID
        configuration.channelProfile = .liveBroadcasting
        let engine = AgoraRtcEngineKit.sharedEngine(with: configuration, delegate: nil)
        guard engine.enableVideo() == 0,
            engine.enableLocalVideo(false) == 0,
            engine.enableLocalAudio(false) == 0
        else {
            AgoraRtcEngineKit.destroy()
            return nil
        }
        return AgoraRtcPlatform(engine: engine)
    }

    /// 销毁进程级声网共享引擎。
    static func destroyEngine() {
        AgoraRtcEngineKit.destroy()
    }

    /// 应用上传视频的编码配置。
    ///
    /// - Parameter configuration: 尺寸、帧率、码率和编码偏好。
    /// - Throws: 厂商引擎拒绝配置时抛出错误。
    func configureVideoEncoding(
        _ configuration: VideoEncodingConfiguration
    ) throws {
        try lock.withLock {
            try applyVideoConfiguration(configuration)
            videoConfiguration = configuration
        }
    }

    /// 启用外部视频输入。
    ///
    /// - Throws: 视频源配置失败时抛出错误。
    func useExternalVideoSource() throws {
        try lock.withLock {
            videoFrameCache.removeAll()
            engine.setExternalVideoSource(true, useTexture: false, sourceType: .videoFrame)
            videoMirrorMode = .disabled
            try reapplyVideoConfiguration()
        }
    }

    /// 更新上传视频镜像。
    ///
    /// - Parameter position: 当前摄像头位置。
    /// - Throws: 编码镜像配置失败时抛出错误。
    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws {
        try lock.withLock {
            videoMirrorMode = position == .front ? .enabled : .disabled
            try reapplyVideoConfiguration()
        }
    }

    /// 切换至麦克风输入并开始采集。
    ///
    /// - Throws: 音频源切换或采集失败时抛出错误。
    func startAudioCapture() throws {
        try lock.withLock {
            try stopExternalAudioSource()
            try Self.checkResult(engine.enableLocalAudio(true), operation: "enableLocalAudio")
        }
    }

    /// 停止麦克风采集。
    ///
    /// - Throws: 厂商引擎停止采集失败时抛出错误。
    func stopAudioCapture() throws {
        try lock.withLock {
            try Self.checkResult(engine.enableLocalAudio(false), operation: "enableLocalAudio")
        }
    }

    /// 启用外部 PCM 输入。
    ///
    /// - Throws: 外部音频轨创建失败时抛出错误。
    func startExternalAudioSource() throws {
        try lock.withLock {
            guard audioTrackID == nil else { return }
            try Self.checkResult(engine.enableLocalAudio(false), operation: "enableLocalAudio")

            let config = AgoraAudioTrackConfig()
            config.enableLocalPlayback = false
            config.enableAudioProcessing = false
            let id = engine.createCustomAudioTrack(.direct, config: config)
            try Self.checkResult(id, operation: "createCustomAudioTrack")
            audioTrackID = Int(id)
        }
    }

    /// 停止外部 PCM 输入并释放音频轨。
    ///
    /// - Throws: 音频轨释放失败时抛出错误。
    func stopExternalAudioSource() throws {
        try lock.withLock {
            guard let id = audioTrackID else { return }
            try Self.checkResult(
                engine.destroyCustomAudioTrack(id), operation: "destroyCustomAudioTrack")
            audioTrackID = nil
        }
    }

    /// 推送外部视频帧。
    ///
    /// - Parameter frame: SDK 中性视频帧。
    /// - Throws: 帧格式或数据无效时抛出错误。
    func pushExternalVideoFrame(
        _ frame: VideoFrame
    ) throws {
        try lock.withLock {
            let converted = try videoFrameCache.frame(for: frame)
            _ = withExtendedLifetime(converted) {
                engine.pushExternalVideoFrame(converted.value, videoTrackId: 0)
            }
        }
    }

    /// 推送外部音频帧。
    ///
    /// - Parameter frame: 带时间戳的 10 ms PCM 数据。
    /// - Throws: 帧格式或数据无效时抛出错误。
    func pushExternalAudioFrame(
        _ frame: AudioFrame
    ) throws {
        let data = try RtcAudioConverter.convertFrame(frame)
        lock.withLock {
            guard let audioTrackID else { return }
            data.withUnsafeBytes { bytes in
                _ = engine.pushExternalAudioFrameRawData(
                    UnsafeMutableRawPointer(mutating: bytes.baseAddress!),
                    samples: AudioFrame.samplesPerFrame,
                    sampleRate: 48000,
                    channels: AudioFrame.channelCount,
                    trackId: audioTrackID,
                    timestamp: Double(frame.timestampUs) / 1000
                )
            }
        }
    }

    /// 创建独立的房间适配对象，尚不发起连接。
    ///
    /// - Parameter roomID: 服务端分配的 RTC 房间标识。
    /// - Returns: 尚未加入的房间。
    /// - Throws: 已存在未释放房间时抛出错误。
    func createRoom(
        roomID: String
    ) throws -> any RtcRoom {
        try lock.withLock {
            guard room == nil || room?.isClosed == true else {
                throw XmaxError(code: .rtcError, message: "RTC room is already active")
            }
            let room = AgoraRtcRoom(platform: self, roomID: roomID)
            self.room = room
            return room
        }
    }

    /// 重新应用已保存的编码配置和当前镜像设置。
    ///
    /// - Throws: 声网拒绝编码配置时抛出错误。
    func reapplyVideoConfiguration() throws {
        if let videoConfiguration {
            try applyVideoConfiguration(videoConfiguration)
        }
    }

    /// 将声网负返回码转换为 RTC 错误。
    ///
    /// - Parameters:
    ///   - result: 平台调用返回码。
    ///   - operation: 用于错误描述的操作名称。
    /// - Throws: 返回码为负数时抛出错误。
    static func checkResult<T: BinaryInteger>(
        _ result: T,
        operation: String
    ) throws {
        if result < 0 {
            throw XmaxError(code: .rtcError, message: "\(operation) failed: \(result)")
        }
    }

    /// 将编码配置应用到活动连接或全局引擎。
    ///
    /// - Parameter configuration: 待应用的视频编码配置。
    /// - Throws: 声网编码配置失败时抛出错误。
    private func applyVideoConfiguration(
        _ configuration: VideoEncodingConfiguration
    ) throws {
        let rtcConfiguration = RtcVideoConverter.makeEncoderConfiguration(configuration)
        rtcConfiguration.mirrorMode = videoMirrorMode
        let result: Int32
        if let room, room.isJoined, !room.isClosed {
            result = engine.setVideoEncoderConfigurationEx(
                rtcConfiguration, connection: room.connection)
        } else {
            result = engine.setVideoEncoderConfiguration(rtcConfiguration)
        }
        try Self.checkResult(result, operation: "setVideoEncoderConfiguration")
    }
}
