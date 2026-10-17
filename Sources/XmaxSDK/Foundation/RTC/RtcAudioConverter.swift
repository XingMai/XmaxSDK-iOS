import Foundation

/// 校验 RTC 外部音频使用的 48 kHz、单声道 PCM16 数据。
enum RtcAudioConverter {
    static func convertFrame(_ frame: AudioFrame) throws -> Data {
        let expectedByteCount = AudioFrame.samplesPerFrame * AudioFrame.channelCount * MemoryLayout<Int16>.size
        guard frame.data.count == expectedByteCount else {
            throw XmaxError(code: .invalidConfiguration, message: "Audio frame must contain exactly \(expectedByteCount) bytes")
        }
        return frame.data
    }
}
