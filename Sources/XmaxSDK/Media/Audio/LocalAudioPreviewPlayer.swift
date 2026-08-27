@preconcurrency import AVFoundation
import Foundation

/// 播放与 RTC 外部音频源共用的 PCM 帧。
final class LocalAudioPreviewPlayer: @unchecked Sendable {

    // 音频配置
    private static let previewVolume: Float = 0.45

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
    private var hasConfiguredPlaybackSession = false

    init() {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(AudioFrame.sampleRate),
            channels: AVAudioChannelCount(AudioFrame.channelCount),
            interleaved: false
        )!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        playerNode.volume = Self.previewVolume
    }

    /// 启用或停止本地音频预览，不影响同一 PCM 帧继续送入 RTC。
    func setPlaybackEnabled(_ enabled: Bool) {
        queue.async { [self] in
            guard isPlaybackEnabled != enabled else { return }
            isPlaybackEnabled = enabled
            if !enabled {
                playerNode.volume = Self.previewVolume
                stopPlayback()
            }
        }
    }

    /// 静音或恢复本地音频预览，不停止播放器和音频引擎。
    func setMuted(_ muted: Bool) {
        queue.async { [self] in
            playerNode.volume = muted ? 0 : Self.previewVolume
        }
    }

    /// 将一帧 PCM 数据加入本地播放队列。
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
                XmaxLogger.error(
                    "本地音频预览失败 (Local Audio Preview Failed)\n" +
                        "└─ 原因：\((error as NSError).localizedDescription)",
                    category: "Media"
                )
            }
        }
    }

    /// 停止播放并等待先前排队的音频操作全部结束。
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                isPlaybackEnabled = false
                playerNode.volume = Self.previewVolume
                stopPlayback()
                continuation.resume()
            }
        }
    }
}

private extension LocalAudioPreviewPlayer {
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

    func stopPlayback() {
        playerNode.stop()
        engine.stop()
        engine.reset()
    }
}
