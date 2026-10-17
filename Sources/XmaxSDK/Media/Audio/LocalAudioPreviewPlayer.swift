//
//  LocalAudioPreviewPlayer.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import Foundation

/// 播放与 RTC 外部音频源共用的 PCM 帧。
final class LocalAudioPreviewPlayer: @unchecked Sendable {

    // 音频配置
    static let defaultVolume: Float = 0.45

    // 平台资源
    private let audioSession = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let queue = DispatchQueue(
        label: "ai.xmax.sdk.local-audio-preview",
        qos: .userInteractive
    )

    // 运行状态
    private var isPlaybackEnabled = false
    private var isMuted = false
    private var volume = LocalAudioPreviewPlayer.defaultVolume
    private var hasConfiguredPlaybackSession = false

    /// 创建用于播放单声道浮点 PCM 的音频引擎和节点。
    init() {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(AudioFrame.sampleRate),
            channels: AVAudioChannelCount(AudioFrame.channelCount),
            interleaved: false
        )!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        playerNode.volume = Self.defaultVolume
    }

    // 播放音量
    /// 当前本地音频预览音量。
    var currentVolume: Float {
        queue.sync { volume }
    }

    /// 开始接收并播放本地预览 PCM 帧。
    func start() {
        queue.async { [self] in
            guard !isPlaybackEnabled else { return }
            isPlaybackEnabled = true
            applyVolume()
        }
    }

    /// 静音或恢复本地音频预览，不停止播放时间轴。
    ///
    /// - Parameter muted: 是否将播放节点音量置零。
    func setMuted(_ muted: Bool) {
        queue.async { [self] in
            isMuted = muted
            applyVolume()
        }
    }

    /// 设置本地音频预览的恢复音量。
    ///
    /// - Parameter volume: 已校验的音量，范围为 `0...1`。
    func setVolume(_ volume: Float) {
        queue.async { [self] in
            self.volume = volume
            applyVolume()
        }
    }

    /// 将固定长度 PCM 帧加入本地串行播放队列。
    ///
    /// - Parameter frame: 48 kHz 单声道 PCM16 音频帧。
    func enqueue(_ frame: AudioFrame) {
        queue.async { [self] in
            guard isPlaybackEnabled,
                  let buffer = makeBuffer(frame) else {
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
                    message: "本地音频预览失败 (Local Audio Preview Failed)\n" +
                        "└─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)"
                )
            }
        }
    }

    /// 停止播放并等待先前排队的音频操作全部结束。
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
    /// 根据静音状态将当前音量应用到播放节点。
    func applyVolume() {
        playerNode.volume = isMuted ? 0 : volume
    }

    /// 配置并激活可用于本地媒体播放的音频会话。
    ///
    /// - Throws: 系统音频会话配置或激活失败时抛出错误。
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

    /// 将固定长度 PCM16 转换为音频节点使用的浮点缓冲区。
    ///
    /// - Parameter frame: 待播放的 PCM16 音频帧。
    /// - Returns: 单声道浮点 PCM 缓冲区；帧长度无效或分配失败时返回 `nil`。
    func makeBuffer(_ frame: AudioFrame) -> AVAudioPCMBuffer? {
        guard frame.data.count == AudioFrame.samplesPerFrame *
                MemoryLayout<Int16>.size,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(AudioFrame.samplesPerFrame)
              ),
              let destination = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(AudioFrame.samplesPerFrame)
        frame.data.withUnsafeBytes { source in
            let samples = source.bindMemory(to: Int16.self)
            for index in 0 ..< AudioFrame.samplesPerFrame {
                destination[index] = Float(samples[index]) / 32_768
            }
        }
        return buffer
    }

    /// 停止播放节点和音频引擎并清空引擎状态。
    func stopPlayback() {
        playerNode.stop()
        engine.stop()
        engine.reset()
    }
}
