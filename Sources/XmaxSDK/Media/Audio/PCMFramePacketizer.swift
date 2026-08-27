import Foundation

/// 将解码得到的不定长 PCM 数据整理为 RTC 要求的固定 10 ms 音频帧。
struct PCMFramePacketizer {

    private struct Segment {
        let data: Data?
        let sampleCount: Int
        var consumedSamples = 0
    }

    // 音频配置
    private static let bytesPerSample = MemoryLayout<Int16>.size
    private static let frameByteCount = AudioFrame.samplesPerFrame *
        bytesPerSample

    // 输入状态
    private let totalSamples: Int
    private var segments: [Segment] = []
    private var segmentIndex = 0
    private var timelineWriteCursor = 0

    // 输出状态
    private var outputCursor = 0

    init(totalSamples: Int) {
        self.totalSamples = totalSamples
    }

    mutating func append(_ data: Data, at requestedStartSample: Int) {
        guard !data.isEmpty, timelineWriteCursor < totalSamples else {
            return
        }
        let startSample = max(0, requestedStartSample)
        if startSample > timelineWriteCursor {
            appendSilence(
                sampleCount: min(
                    startSample - timelineWriteCursor,
                    totalSamples - timelineWriteCursor
                )
            )
        }

        let overlapSamples = max(0, timelineWriteCursor - startSample)
        let overlapBytes = min(
            data.count,
            overlapSamples * Self.bytesPerSample
        )
        let availableSamples = (data.count - overlapBytes) /
            Self.bytesPerSample
        let acceptedSamples = min(
            availableSamples,
            totalSamples - timelineWriteCursor
        )
        guard acceptedSamples > 0 else { return }

        let acceptedBytes = acceptedSamples * Self.bytesPerSample
        segments.append(
            Segment(
                data: Data(
                    data[overlapBytes ..< overlapBytes + acceptedBytes]
                ),
                sampleCount: acceptedSamples
            )
        )
        timelineWriteCursor += acceptedSamples
    }

    mutating func finishWithSilence() {
        appendSilence(sampleCount: totalSamples - timelineWriteCursor)
    }

    mutating func nextFrame() -> (data: Data, sampleOffset: Int)? {
        guard timelineWriteCursor - outputCursor >= AudioFrame.samplesPerFrame,
              outputCursor < totalSamples else {
            return nil
        }

        var data = Data(count: Self.frameByteCount)
        var destinationSampleOffset = 0
        while destinationSampleOffset < AudioFrame.samplesPerFrame {
            guard segmentIndex < segments.count else { return nil }
            let availableSamples = segments[segmentIndex].sampleCount -
                segments[segmentIndex].consumedSamples
            let copiedSamples = min(
                availableSamples,
                AudioFrame.samplesPerFrame - destinationSampleOffset
            )
            if let segmentData = segments[segmentIndex].data {
                let sourceStart = segments[segmentIndex].consumedSamples *
                    Self.bytesPerSample
                let sourceEnd = sourceStart + copiedSamples *
                    Self.bytesPerSample
                let destinationStart = destinationSampleOffset *
                    Self.bytesPerSample
                let destinationEnd = destinationStart + copiedSamples *
                    Self.bytesPerSample
                data.replaceSubrange(
                    destinationStart ..< destinationEnd,
                    with: segmentData[sourceStart ..< sourceEnd]
                )
            }
            segments[segmentIndex].consumedSamples += copiedSamples
            destinationSampleOffset += copiedSamples
            if segments[segmentIndex].consumedSamples ==
                segments[segmentIndex].sampleCount {
                segmentIndex += 1
            }
        }

        let sampleOffset = outputCursor
        outputCursor += AudioFrame.samplesPerFrame
        return (data, sampleOffset)
    }

    private mutating func appendSilence(sampleCount: Int) {
        guard sampleCount > 0 else { return }
        segments.append(Segment(data: nil, sampleCount: sampleCount))
        timelineWriteCursor += sampleCount
    }
}
