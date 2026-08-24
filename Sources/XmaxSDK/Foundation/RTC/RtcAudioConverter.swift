import Foundation
@preconcurrency import VolcEngineRTC

/// 将中性 PCM 音频帧转换为火山 RTC 音频帧。
enum RtcAudioConverter {

    /// 创建 48 kHz、单声道、PCM16 火山 RTC 音频帧。
    static func convertFrame(_ frame: AudioFrame) throws -> ByteRTCAudioFrame {
        let expectedByteCount = AudioFrame.samplesPerFrame *
            AudioFrame.channelCount * MemoryLayout<Int16>.size
        guard frame.data.count == expectedByteCount else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Audio frame must contain exactly \(expectedByteCount) bytes"
            )
        }

        let rtcFrame = ByteRTCAudioFrame()
        rtcFrame.buffer = frame.data
        rtcFrame.samples = Int32(AudioFrame.samplesPerFrame)
        rtcFrame.channel = .mono
        rtcFrame.sampleRate = .rate48000
        return rtcFrame
    }
}
