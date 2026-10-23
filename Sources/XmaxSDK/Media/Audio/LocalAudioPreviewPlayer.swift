//
//  LocalAudioPreviewPlayer.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import Foundation

/// A PCM frame shared by playback and external RTC audio.
final class LocalAudioPreviewPlayer: @unchecked Sendable {

    /// The default local preview volume, from 0 to 1.
    static let defaultVolume: Float = 0.45

    /// The local preview audio session.
    private let audioSession = AVAudioSession.sharedInstance()

    /// The engine playing local PCM audio.
    private let engine = AVAudioEngine()

    /// The PCM playback node.
    private let playerNode = AVAudioPlayerNode()

    /// The playback format matching local PCM.
    private let format: AVAudioFormat

    /// The queue serializing playback and state updates.
    private let queue = DispatchQueue(
        label: "ai.xmax.sdk.local-audio-preview",
        qos: .userInteractive
    )

    /// Whether local audio frames are accepted.
    private var isPlaybackEnabled = false

    /// Whether local preview is temporarily muted.
    private var isMuted = false

    /// The local preview volume, from 0 to 1.
    private var volume = LocalAudioPreviewPlayer.defaultVolume

    /// Whether the preview playback session has been configured.
    private var hasConfiguredPlaybackSession = false

    /// Creates a mono floating-point PCM preview player.
    init() {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(AudioFrame.sampleRate),
            channels: AVAudioChannelCount(AudioFrame.channelCount),
            interleaved: false
        )!
        engine.attach(playerNode)
        engine.connect(
            playerNode,
            to: engine.mainMixerNode,
            format: format
        )
        playerNode.volume = Self.defaultVolume
    }

    /// The local audio preview volume.
    var currentVolume: Float {
        queue.sync {
            volume
        }
    }

    /// Starts local PCM preview playback.
    func start() {
        queue.async { [self] in
            guard !isPlaybackEnabled else {
                return
            }
            isPlaybackEnabled = true
            applyVolume()
        }
    }

    /// Mutes or restores local preview without stopping its timeline.
    ///
    /// - Parameter muted: Whether to mute the playback node.
    func setMuted(
        _ muted: Bool
    ) {
        queue.async { [self] in
            isMuted = muted
            applyVolume()
        }
    }

    /// Sets the unmuted local preview volume.
    ///
    /// - Parameter volume: The validated volume, in the range `0...1`.
    func setVolume(
        _ volume: Float
    ) {
        queue.async { [self] in
            self.volume = volume
            applyVolume()
        }
    }

    /// Enqueues a fixed-size PCM frame for local playback.
    ///
    /// - Parameter frame: A 48 kHz mono PCM16 frame.
    func enqueue(
        _ frame: AudioFrame
    ) {
        queue.async { [self] in
            guard isPlaybackEnabled,
                let buffer = makeBuffer(frame)
            else {
                return
            }

            do {
                if !engine.isRunning {
                    try activateAudioSession()
                    engine.prepare()
                    try engine.start()
                }
                playerNode.scheduleBuffer(buffer)
                if !playerNode.isPlaying {
                    playerNode.play()
                }
            } catch {
                stopPlayback()
                XmaxLogger.media.error(
                    message: "本地音频预览失败 (Local Audio Preview Failed)\n"
                        + "└─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)"
                )
            }
        }
    }

    /// Stops playback and waits for queued audio operations.
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                isPlaybackEnabled = false
                isMuted = false
                applyVolume()
                stopPlayback()
                continuation.resume()
            }
        }
    }
}

private extension LocalAudioPreviewPlayer {

    /// Applies volume according to the mute state.
    func applyVolume() {
        playerNode.volume = isMuted ? 0 : volume
    }

    /// Configures and activates the local media playback audio session.
    ///
    /// - Throws: An error if audio session configuration or activation fails.
    func activateAudioSession() throws {
        if !hasConfiguredPlaybackSession {
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                options: []
            )
            hasConfiguredPlaybackSession = true
        }
        try audioSession.setActive(true)
    }

    /// Converts fixed-size PCM16 to a playback buffer.
    ///
    /// - Parameter frame: The PCM16 frame to play.
    ///
    /// - Returns: A mono floating-point buffer, or `nil` if its length is invalid or allocation
    ///   fails.
    func makeBuffer(
        _ frame: AudioFrame
    ) -> AVAudioPCMBuffer? {
        guard frame.data.count == AudioFrame.samplesPerFrame * MemoryLayout<Int16>.size,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(AudioFrame.samplesPerFrame)
            ),
            let destination = buffer.floatChannelData?[0]
        else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(AudioFrame.samplesPerFrame)
        frame.data.withUnsafeBytes { source in
            let samples = source.bindMemory(to: Int16.self)
            for index in 0..<AudioFrame.samplesPerFrame {
                destination[index] = Float(samples[index]) / 32_768
            }
        }
        return buffer
    }

    /// Stops the audio engine and playback node.
    func stopPlayback() {
        playerNode.stop()
        engine.stop()
        engine.reset()
    }
}
