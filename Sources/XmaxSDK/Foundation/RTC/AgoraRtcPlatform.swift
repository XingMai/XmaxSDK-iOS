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

/// An Agora adapter for RTC engine operations.
final class AgoraRtcPlatform: RtcPlatform, @unchecked Sendable {

    /// The initialized Agora engine.
    let engine: AgoraRtcEngineKit

    /// The lock serializing engine configuration and room operations.
    let lock = NSRecursiveLock()

    /// The room owned by this platform instance.
    private weak var room: AgoraRtcRoom?

    /// The cached Agora external video frame.
    private let videoFrameCache = RtcVideoFrameCache()

    /// The most recently applied encoder configuration.
    private var videoConfiguration: VideoEncodingConfiguration?

    /// The local encoder mirror mode.
    private var videoMirrorMode = AgoraVideoMirrorMode.disabled

    /// The external audio track identifier.
    private(set) var audioTrackID: Int?

    /// Creates a platform adapter for an Agora engine.
    private init(
        engine: AgoraRtcEngineKit
    ) {
        self.engine = engine
    }

    /// Creates an Agora engine with default camera and microphone capture disabled.
    ///
    /// - Parameter appID: The Agora application identifier.
    ///
    /// - Returns: The platform adapter, or `nil` if configuration fails.
    static func create(
        appID: String
    ) -> (any RtcPlatform)? {
        let configuration = AgoraRtcEngineConfig()
        configuration.appId = appID
        configuration.channelProfile = .liveBroadcasting
        let engine = AgoraRtcEngineKit.sharedEngine(
            with: configuration,
            delegate: nil
        )
        guard engine.enableVideo() == 0,
            engine.enableLocalVideo(false) == 0,
            engine.enableLocalAudio(false) == 0
        else {
            AgoraRtcEngineKit.destroy()
            return nil
        }

        return AgoraRtcPlatform(engine: engine)
    }

    /// Destroys the process-wide Agora engine.
    static func destroyEngine() {
        AgoraRtcEngineKit.destroy()
    }

    /// Applies the uplink encoder configuration.
    ///
    /// - Parameter configuration: The dimensions, frame rate, bitrate, and encoding preference.
    ///
    /// - Throws: An error if the engine rejects the configuration.
    func configureVideoEncoding(
        _ configuration: VideoEncodingConfiguration
    ) throws {
        try lock.withLock {
            try applyVideoConfiguration(configuration)
            videoConfiguration = configuration
        }
    }

    /// Enables external video input.
    ///
    /// - Throws: An error if video source configuration fails.
    func useExternalVideoSource() throws {
        try lock.withLock {
            videoFrameCache.removeAll()
            engine.setExternalVideoSource(
                true,
                useTexture: false,
                sourceType: .videoFrame
            )
            videoMirrorMode = .disabled
            try reapplyVideoConfiguration()
        }
    }

    /// Updates uplink video mirroring.
    ///
    /// - Parameter position: The current camera position.
    ///
    /// - Throws: An error if encoder mirroring cannot be configured.
    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws {
        try lock.withLock {
            videoMirrorMode = position == .front ? .enabled : .disabled
            try reapplyVideoConfiguration()
        }
    }

    /// Switches to microphone input and starts capture.
    ///
    /// - Throws: An error if source switching or capture fails.
    func startAudioCapture() throws {
        try lock.withLock {
            try stopExternalAudioSource()
            try Self.checkResult(
                engine.enableLocalAudio(true),
                operation: "enableLocalAudio"
            )
        }
    }

    /// Stops microphone capture.
    ///
    /// - Throws: An error if the engine cannot stop capture.
    func stopAudioCapture() throws {
        try lock.withLock {
            try Self.checkResult(
                engine.enableLocalAudio(false),
                operation: "enableLocalAudio"
            )
        }
    }

    /// Enables external PCM input.
    ///
    /// - Throws: An error if the external audio track cannot be created.
    func startExternalAudioSource() throws {
        try lock.withLock {
            guard audioTrackID == nil else {
                return
            }
            try Self.checkResult(
                engine.enableLocalAudio(false),
                operation: "enableLocalAudio"
            )

            let config = AgoraAudioTrackConfig()
            config.enableLocalPlayback = false
            config.enableAudioProcessing = false
            let id = engine.createCustomAudioTrack(
                .direct,
                config: config
            )
            try Self.checkResult(
                id,
                operation: "createCustomAudioTrack"
            )
            audioTrackID = Int(id)
        }
    }

    /// Stops external PCM input and releases its track.
    ///
    /// - Throws: An error if the audio track cannot be released.
    func stopExternalAudioSource() throws {
        try lock.withLock {
            guard let id = audioTrackID else {
                return
            }
            try Self.checkResult(
                engine.destroyCustomAudioTrack(id),
                operation: "destroyCustomAudioTrack"
            )
            audioTrackID = nil
        }
    }

    /// Pushes an external video frame.
    ///
    /// - Parameter frame: The SDK video frame.
    ///
    /// - Throws: An error if the frame format or data is invalid.
    func pushExternalVideoFrame(
        _ frame: VideoFrame
    ) throws {
        try lock.withLock {
            let converted = try videoFrameCache.frame(for: frame)
            _ = withExtendedLifetime(converted) {
                engine.pushExternalVideoFrame(
                    converted.value,
                    videoTrackId: 0
                )
            }
        }
    }

    /// Pushes an external audio frame.
    ///
    /// - Parameter frame: A timestamped 10 ms PCM frame.
    ///
    /// - Throws: An error if the frame format or data is invalid.
    func pushExternalAudioFrame(
        _ frame: AudioFrame
    ) throws {
        let data = try RtcAudioConverter.convertFrame(frame)
        lock.withLock {
            guard let audioTrackID else {
                return
            }

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

    /// Creates a room adapter without connecting.
    ///
    /// - Parameter roomID: The server-assigned RTC room identifier.
    ///
    /// - Returns: An unjoined room.
    ///
    /// - Throws: An error if an unreleased room already exists.
    func createRoom(
        roomID: String
    ) throws -> any RtcRoom {
        try lock.withLock {
            guard room == nil || room?.isClosed == true else {
                throw XmaxError(
                    code: .rtcError,
                    message: "RTC room is already active"
                )
            }

            let room = AgoraRtcRoom(
                platform: self,
                roomID: roomID
            )
            self.room = room
            return room
        }
    }

    /// Reapplies the saved encoder configuration and mirror setting.
    ///
    /// - Throws: An error if Agora rejects the encoder configuration.
    func reapplyVideoConfiguration() throws {
        if let videoConfiguration {
            try applyVideoConfiguration(videoConfiguration)
        }
    }

    /// Converts a negative Agora return code to an RTC error.
    ///
    /// - Parameters:
    ///   - result: The platform return code.
    ///   - operation: The operation name for the error message.
    ///
    /// - Throws: An error if the return code is negative.
    static func checkResult<T: BinaryInteger>(
        _ result: T,
        operation: String
    ) throws {
        if result < 0 {
            throw XmaxError(
                code: .rtcError,
                message: "\(operation) failed: \(result)"
            )
        }
    }

    /// Applies the encoder configuration to the active connection or engine.
    ///
    /// - Parameter configuration: The encoder configuration to apply.
    ///
    /// - Throws: An error if Agora encoder configuration fails.
    private func applyVideoConfiguration(
        _ configuration: VideoEncodingConfiguration
    ) throws {
        let rtcConfiguration = RtcVideoConverter.makeEncoderConfiguration(configuration)
        rtcConfiguration.mirrorMode = videoMirrorMode
        let result: Int32
        if let room, room.isJoined, !room.isClosed {
            result = engine.setVideoEncoderConfigurationEx(
                rtcConfiguration,
                connection: room.connection
            )
        } else {
            result = engine.setVideoEncoderConfiguration(rtcConfiguration)
        }

        try Self.checkResult(
            result,
            operation: "setVideoEncoderConfiguration"
        )
    }
}
