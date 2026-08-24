import Foundation

/// RTC 外部音频链路使用的 48 kHz 单声道 PCM 音频帧。
struct AudioFrame: Equatable, Sendable {

    static let sampleRate = 48_000
    static let channelCount = 1
    static let samplesPerFrame = 480

    let data: Data
    let timestampUs: Int64
}
