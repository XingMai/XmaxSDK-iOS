import Foundation

/// 为同一文件的音频和视频提供统一的循环播放时钟。
struct MediaPlaybackTimeline: Sendable {

    // 播放时钟
    let anchorNanoseconds: UInt64
    let cycleSampleCount: Int
    let cycleDurationNanoseconds: UInt64

    init(mediaDurationSeconds: Double) {
        let rawSampleCount = Int(
            ceil(mediaDurationSeconds * Double(AudioFrame.sampleRate))
        )
        let packetCount = Int(
            ceil(Double(rawSampleCount) / Double(AudioFrame.samplesPerFrame))
        )
        cycleSampleCount = max(
            AudioFrame.samplesPerFrame,
            packetCount * AudioFrame.samplesPerFrame
        )
        cycleDurationNanoseconds = UInt64(
            Double(cycleSampleCount) /
                Double(AudioFrame.sampleRate) * 1_000_000_000
        )
        anchorNanoseconds = DispatchTime.now().uptimeNanoseconds + 100_000_000
    }

    func target(
        loopIndex: Int,
        mediaOffsetSeconds: Double
    ) -> UInt64 {
        let loopOffset = cycleDurationNanoseconds * UInt64(loopIndex)
        let mediaOffset = UInt64(
            max(0, mediaOffsetSeconds) * 1_000_000_000
        )
        return anchorNanoseconds + loopOffset + mediaOffset
    }

    func target(
        loopIndex: Int,
        sampleOffset: Int
    ) -> UInt64 {
        target(
            loopIndex: loopIndex,
            mediaOffsetSeconds: Double(sampleOffset) /
                Double(AudioFrame.sampleRate)
        )
    }
}
