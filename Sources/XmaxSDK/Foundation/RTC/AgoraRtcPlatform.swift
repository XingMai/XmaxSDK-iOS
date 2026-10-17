//
//  AgoraRtcPlatform.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AgoraRtcKit
import Foundation

/// 将中性引擎操作转换为声网调用。
final class AgoraRtcPlatform: RtcPlatform, @unchecked Sendable {

    // 平台资源
    let engine: AgoraRtcEngineKit
    let lock = NSRecursiveLock()
    private weak var room: AgoraRtcRoom?

    // 视频配置
    private let videoFrameCache = RtcVideoFrameCache()
    private var videoConfiguration: VideoEncodingConfiguration?
    private var videoMirrorMode = AgoraVideoMirrorMode.disabled

    // 音频资源
    private(set) var audioTrackID: Int?

    private init(engine: AgoraRtcEngineKit) {
        self.engine = engine
    }

    static func create(appID: String) -> (any RtcPlatform)? {
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

    static func destroyEngine() {
        AgoraRtcEngineKit.destroy()
    }

    func configureVideoEncoding(_ configuration: VideoEncodingConfiguration) throws {
        try lock.withLock {
            try applyVideoConfiguration(configuration)
            videoConfiguration = configuration
        }
    }

    func useExternalVideoSource() throws {
        try lock.withLock {
            videoFrameCache.removeAll()
            engine.setExternalVideoSource(true, useTexture: false, sourceType: .videoFrame)
            videoMirrorMode = .disabled
            try reapplyVideoConfiguration()
        }
    }

    func configureLocalVideoMirror(for position: CameraPosition) throws {
        try lock.withLock {
            videoMirrorMode = position == .front ? .enabled : .disabled
            try reapplyVideoConfiguration()
        }
    }

    func startAudioCapture() throws {
        try lock.withLock {
            try stopExternalAudioSource()
            try Self.checkResult(engine.enableLocalAudio(true), operation: "enableLocalAudio")
        }
    }

    func stopAudioCapture() throws {
        try lock.withLock {
            try Self.checkResult(engine.enableLocalAudio(false), operation: "enableLocalAudio")
        }
    }

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

    func stopExternalAudioSource() throws {
        try lock.withLock {
            guard let id = audioTrackID else { return }
            try Self.checkResult(
                engine.destroyCustomAudioTrack(id), operation: "destroyCustomAudioTrack")
            audioTrackID = nil
        }
    }

    func pushExternalVideoFrame(_ frame: VideoFrame) throws {
        try lock.withLock {
            let converted = try videoFrameCache.frame(for: frame)
            _ = withExtendedLifetime(converted) {
                engine.pushExternalVideoFrame(converted.value, videoTrackId: 0)
            }
        }
    }

    func pushExternalAudioFrame(_ frame: AudioFrame) throws {
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

    func createRoom(roomID: String) throws -> any RtcRoom {
        try lock.withLock {
            guard room == nil || room?.isClosed == true else {
                throw XmaxError(code: .rtcError, message: "RTC room is already active")
            }
            let room = AgoraRtcRoom(platform: self, roomID: roomID)
            self.room = room
            return room
        }
    }

    func reapplyVideoConfiguration() throws {
        if let videoConfiguration {
            try applyVideoConfiguration(videoConfiguration)
        }
    }

    static func checkResult<T: BinaryInteger>(_ result: T, operation: String) throws {
        if result < 0 {
            throw XmaxError(code: .rtcError, message: "\(operation) failed: \(result)")
        }
    }

    private func applyVideoConfiguration(_ configuration: VideoEncodingConfiguration) throws {
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
