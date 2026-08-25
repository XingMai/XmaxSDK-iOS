import Foundation

/// 将 48 kHz 单声道 PCM16 数据切分为固定 10 ms 音频帧。
final class AudioPCMFramePacketizer {

    // 音频参数
    private static let bytesPerSample = MemoryLayout<Int16>.size
    private static let frameDurationUs: Int64 = 10_000

    // 时间线配置
    private let mediaStartUs: Int64
    private let cycleSampleCount: Int64

    // 运行状态
    private var pendingData = Data()
    private var scheduledSampleCount: Int64 = 0
    private var hasReceivedSourceData = false

    init(
        mediaStartUs: Int64,
        cycleDurationUs: Int64
    ) {
        self.mediaStartUs = mediaStartUs

        let completeFrameCount = cycleDurationUs / Self.frameDurationUs
        let partialFrameCount: Int64 = cycleDurationUs.isMultiple(
            of: Self.frameDurationUs
        ) ? 0 : 1
        cycleSampleCount = max(
            1,
            completeFrameCount + partialFrameCount
        ) * Int64(AudioFrame.samplesPerFrame)
    }

    func append(
        _ data: Data,
        sourceTimestampUs: Int64
    ) -> [AudioFrame] {
        guard data.count.isMultiple(of: Self.bytesPerSample) else {
            return []
        }

        var frames: [AudioFrame] = []
        if !hasReceivedSourceData {
            hasReceivedSourceData = true
            let sourceOffsetUs = max(sourceTimestampUs - mediaStartUs, 0)
            let initialSilenceSamples = sourceOffsetUs
                * Int64(AudioFrame.sampleRate) / 1_000_000
            appendSilence(
                sampleCount: initialSilenceSamples,
                frames: &frames
            )
        }

        appendPCM(data, frames: &frames)
        return frames
    }

    func finish() -> [AudioFrame] {
        var frames: [AudioFrame] = []
        appendSilence(
            sampleCount: cycleSampleCount - scheduledSampleCount,
            frames: &frames
        )
        return frames
    }

    private func appendPCM(
        _ data: Data,
        frames: inout [AudioFrame]
    ) {
        let remainingSampleCount = max(
            cycleSampleCount - scheduledSampleCount,
            0
        )
        let sourceSampleCount = Int64(data.count / Self.bytesPerSample)
        let acceptedSampleCount = min(
            remainingSampleCount,
            sourceSampleCount
        )
        guard acceptedSampleCount > 0 else {
            return
        }

        let acceptedByteCount = Int(acceptedSampleCount)
            * Self.bytesPerSample
        pendingData.append(data.prefix(acceptedByteCount))
        scheduledSampleCount += acceptedSampleCount
        emitCompleteFrames(into: &frames)
    }

    private func appendSilence(
        sampleCount: Int64,
        frames: inout [AudioFrame]
    ) {
        var remainingSampleCount = min(
            max(sampleCount, 0),
            cycleSampleCount - scheduledSampleCount
        )
        while remainingSampleCount > 0 {
            let pendingSampleCount = pendingData.count
                / Self.bytesPerSample
            let availableSampleCount = AudioFrame.samplesPerFrame
                - pendingSampleCount
            let appendedSampleCount = min(
                Int64(availableSampleCount),
                remainingSampleCount
            )
            pendingData.append(Data(
                repeating: 0,
                count: Int(appendedSampleCount) * Self.bytesPerSample
            ))
            scheduledSampleCount += appendedSampleCount
            remainingSampleCount -= appendedSampleCount
            emitCompleteFrames(into: &frames)
        }
    }

    private func emitCompleteFrames(
        into frames: inout [AudioFrame]
    ) {
        let frameByteCount = AudioFrame.samplesPerFrame
            * Self.bytesPerSample
        while pendingData.count >= frameByteCount {
            let emittedSampleCount = scheduledSampleCount
                - Int64(pendingData.count / Self.bytesPerSample)
            let timestampUs = mediaStartUs
                + emittedSampleCount * 1_000_000
                / Int64(AudioFrame.sampleRate)
            let frameData = Data(pendingData.prefix(frameByteCount))
            pendingData.removeFirst(frameByteCount)
            frames.append(AudioFrame(
                data: frameData,
                timestampUs: timestampUs
            ))
        }
    }
}
