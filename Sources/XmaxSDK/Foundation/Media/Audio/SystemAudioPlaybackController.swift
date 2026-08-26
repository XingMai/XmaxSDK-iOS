@preconcurrency import AVFoundation
import Foundation

/// 使用系统音频引擎播放 48 kHz 单声道 PCM16 数据。
final class SystemAudioPlaybackController: AudioPlaybackControlling, @unchecked Sendable {

    // 播放资源
    private let audioSession = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    // 运行状态
    private var isStarted = false

    init() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(AudioFrame.sampleRate),
            channels: AVAudioChannelCount(AudioFrame.channelCount),
            interleaved: true
        ) else {
            throw Self.playbackError("Failed to create PCM audio format")
        }
        self.format = format
    }

    deinit {
        stop()
    }

    func start() throws {
        guard !isStarted else {
            return
        }

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try audioSession.setActive(true)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.play()
            isStarted = true
        } catch {
            player.stop()
            engine.stop()
            if engine.attachedNodes.contains(player) {
                engine.detach(player)
            }
            throw Self.playbackError((error as NSError).localizedDescription)
        }
    }

    func enqueue(_ data: Data) throws {
        guard isStarted else {
            return
        }

        let buffer = try Self.makeBuffer(data: data, format: format)
        player.scheduleBuffer(buffer)
    }

    func flush() throws {
        guard isStarted else {
            return
        }

        player.stop()
        player.play()
    }

    func stop() {
        guard isStarted else {
            return
        }

        isStarted = false
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.detach(player)
    }

    /// 将交错排列的 PCM16 数据转换为系统音频缓冲区。
    static func makeBuffer(
        data: Data,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let bytesPerFrame = MemoryLayout<Int16>.size * AudioFrame.channelCount
        guard !data.isEmpty, data.count.isMultiple(of: bytesPerFrame) else {
            throw playbackError("PCM audio data length is invalid")
        }

        let frameCount = data.count / bytesPerFrame
        guard frameCount <= Int(AVAudioFrameCount.max),
              data.count <= Int(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let destination = buffer.mutableAudioBufferList.pointee
                  .mBuffers.mData else {
            throw playbackError("Failed to create PCM audio buffer")
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        data.copyBytes(
            to: destination.assumingMemoryBound(to: UInt8.self),
            count: data.count
        )
        buffer.mutableAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(
            data.count
        )
        return buffer
    }

    private static func playbackError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
