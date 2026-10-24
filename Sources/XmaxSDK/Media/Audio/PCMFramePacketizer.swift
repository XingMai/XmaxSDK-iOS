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

/// Packetizes decoded PCM into fixed 10 ms RTC audio frames.
struct PCMFramePacketizer {

    /// An audio or silence segment and its consumed samples.
    private struct Segment {

        /// The PCM data, or `nil` for silence.
        let data: Data?

        /// The segment's sample count.
        let sampleCount: Int

        /// The consumed sample count.
        var consumedSamples = 0
    }

    /// The bytes per PCM16 sample.
    private static let bytesPerSample = MemoryLayout<Int16>.size

    /// The bytes per 10 ms packet.
    private static let frameByteCount = AudioFrame.samplesPerFrame * bytesPerSample

    /// The optional sample limit for a finite playback cycle.
    private let totalSamples: Int?

    /// The pending audio and silence segments.
    private var segments: [Segment] = []

    /// The segment being consumed.
    private var segmentIndex = 0

    /// The samples written in this playback cycle.
    private var timelineWriteCursor = 0

    /// The samples emitted in this playback cycle.
    private var outputCursor = 0

    /// Creates a PCM packetizer with an optional playback cycle limit.
    init(
        totalSamples: Int? = nil
    ) {
        self.totalSamples = totalSamples
    }

    /// Appends PCM at a sample position, filling gaps and skipping overlaps.
    ///
    /// - Parameters:
    ///   - data: The mono PCM16 data.
    ///   - requestedStartSample: The starting sample position in this cycle.
    mutating func append(
        _ data: Data,
        at requestedStartSample: Int
    ) {
        let sampleLimit = totalSamples ?? Int.max
        guard !data.isEmpty, timelineWriteCursor < sampleLimit else {
            return
        }

        let startSample = max(
            0,
            requestedStartSample
        )
        if startSample > timelineWriteCursor {
            appendSilence(
                sampleCount: min(
                    startSample - timelineWriteCursor,
                    sampleLimit - timelineWriteCursor
                )
            )
        }

        let overlapSamples = max(
            0,
            timelineWriteCursor - startSample
        )
        let overlapBytes = min(
            data.count,
            overlapSamples * Self.bytesPerSample
        )
        let availableSamples = (data.count - overlapBytes) / Self.bytesPerSample
        let acceptedSamples = min(
            availableSamples,
            sampleLimit - timelineWriteCursor
        )
        guard acceptedSamples > 0 else {
            return
        }

        let acceptedBytes = acceptedSamples * Self.bytesPerSample
        segments.append(
            Segment(
                data: Data(
                    data[overlapBytes..<overlapBytes + acceptedBytes]
                ),
                sampleCount: acceptedSamples
            )
        )
        timelineWriteCursor += acceptedSamples
    }

    /// Pads the rest of the playback cycle with silence.
    mutating func finishWithSilence() {
        guard let totalSamples else {
            return
        }
        appendSilence(sampleCount: totalSamples - timelineWriteCursor)
    }

    /// Returns the next complete 10 ms PCM frame.
    ///
    /// - Returns: The audio and cycle sample offset, or `nil` if no complete frame remains.
    mutating func nextFrame() -> (data: Data, sampleOffset: Int)? {
        guard timelineWriteCursor - outputCursor >= AudioFrame.samplesPerFrame else {
            return nil
        }

        var data = Data(count: Self.frameByteCount)
        var destinationSampleOffset = 0

        while destinationSampleOffset < AudioFrame.samplesPerFrame {
            guard segmentIndex < segments.count else {
                return nil
            }

            let availableSamples =
                segments[segmentIndex].sampleCount - segments[segmentIndex].consumedSamples
            let copiedSamples = min(
                availableSamples,
                AudioFrame.samplesPerFrame - destinationSampleOffset
            )
            if let segmentData = segments[segmentIndex].data {
                let sourceStart = segments[segmentIndex].consumedSamples * Self.bytesPerSample
                let sourceEnd = sourceStart + copiedSamples * Self.bytesPerSample
                let destinationStart = destinationSampleOffset * Self.bytesPerSample
                let destinationEnd = destinationStart + copiedSamples * Self.bytesPerSample
                data.replaceSubrange(
                    destinationStart..<destinationEnd,
                    with: segmentData[sourceStart..<sourceEnd]
                )
            }

            segments[segmentIndex].consumedSamples += copiedSamples
            destinationSampleOffset += copiedSamples
            if segments[segmentIndex].consumedSamples == segments[segmentIndex].sampleCount {
                segmentIndex += 1
            }
        }

        let sampleOffset = outputCursor
        outputCursor += AudioFrame.samplesPerFrame
        if segmentIndex > 0 {
            segments.removeFirst(segmentIndex)
            segmentIndex = 0
        }
        return (data, sampleOffset)
    }

    /// Appends silence to the input timeline.
    ///
    /// - Parameter sampleCount: The sample count to append. Nonpositive values are ignored.
    private mutating func appendSilence(
        sampleCount: Int
    ) {
        guard sampleCount > 0 else {
            return
        }
        segments.append(
            Segment(
                data: nil,
                sampleCount: sampleCount
            )
        )
        timelineWriteCursor += sampleCount
    }
}
