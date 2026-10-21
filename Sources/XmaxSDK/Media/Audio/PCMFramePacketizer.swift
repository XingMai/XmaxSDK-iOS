//
//  PCMFramePacketizer.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 将解码得到的不定长 PCM 数据整理为 RTC 要求的固定 10 ms 音频帧。
struct PCMFramePacketizer {

    /// 保存一段实际 PCM 或静音样本及其消费进度。
    private struct Segment {

        /// 该段 PCM 数据；nil 表示对应长度的静音。
        let data: Data?

        /// 该段实际音频或静音包含的采样数。
        let sampleCount: Int

        /// 该段已被分帧器消费的采样数。
        var consumedSamples = 0
    }

    /// 单个 PCM16 采样占用的字节数。
    private static let bytesPerSample = MemoryLayout<Int16>.size

    /// 一个固定 10 ms PCM 包占用的字节数。
    private static let frameByteCount = AudioFrame.samplesPerFrame *
        bytesPerSample

    /// 当前播放周期的总采样数，应按固定帧采样数对齐。
    private let totalSamples: Int

    /// 等待消费的音频与静音片段。
    private var segments: [Segment] = []

    /// 当前正在消费的片段索引。
    private var segmentIndex = 0

    /// 当前播放周期中已写入的采样位置。
    private var timelineWriteCursor = 0

    /// 当前播放周期中已输出的采样位置。
    private var outputCursor = 0

    /// 创建限定总采样长度的 PCM 分帧器。
    init(
        totalSamples: Int
    ) {
        self.totalSamples = totalSamples
    }

    /// 按采样位置追加 PCM，补齐空隙并跳过重叠样本。
    ///
    /// - Parameters:
    ///   - data: 单声道 PCM16 数据。
    ///   - requestedStartSample: 数据在当前周期内的起始采样位置。
    mutating func append(
        _ data: Data,
        at requestedStartSample: Int
    ) {
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

    /// 使用静音样本补齐当前周期剩余长度。
    mutating func finishWithSilence() {
        appendSilence(sampleCount: totalSamples - timelineWriteCursor)
    }

    /// 取出下一帧完整的 10 ms PCM 数据。
    ///
    /// - Returns: 音频数据及其周期内采样偏移；不足一帧或已结束时返回 `nil`。
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

    /// 向输入时间轴追加静音样本。
    ///
    /// - Parameter sampleCount: 需要补齐的采样数；非正值不追加。
    private mutating func appendSilence(
        sampleCount: Int
    ) {
        guard sampleCount > 0 else { return }
        segments.append(Segment(data: nil, sampleCount: sampleCount))
        timelineWriteCursor += sampleCount
    }
}
