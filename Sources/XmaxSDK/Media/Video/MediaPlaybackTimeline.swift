//
//  MediaPlaybackTimeline.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A shared looping playback clock for file audio and video.
struct MediaPlaybackTimeline: Sendable {

    /// The first cycle's monotonic host start time, in nanoseconds.
    let anchorNanoseconds: UInt64

    /// The samples per cycle, aligned to complete PCM packets.
    let cycleSampleCount: Int

    /// The cycle duration, in nanoseconds.
    let cycleDurationNanoseconds: UInt64

    /// Creates a playback clock with cycles aligned to complete PCM packets.
    ///
    /// - Parameter mediaDurationSeconds: The validated positive, finite media duration, in seconds.
    init(
        mediaDurationSeconds: Double
    ) {
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
            Double(cycleSampleCount) / Double(AudioFrame.sampleRate) * 1_000_000_000
        )
        anchorNanoseconds = DispatchTime.now().uptimeNanoseconds + 100_000_000
    }

    /// Maps a media offset to its host playback time.
    ///
    /// - Parameters:
    ///   - loopIndex: The zero-based playback cycle.
    ///   - mediaOffsetSeconds: The offset within this cycle, in seconds.
    ///
    /// - Returns: The monotonic host timestamp, in nanoseconds.
    func target(
        loopIndex: Int,
        mediaOffsetSeconds: Double
    ) -> UInt64 {
        let loopOffset = cycleDurationNanoseconds * UInt64(loopIndex)
        let mediaOffset = UInt64(
            max(
                0,
                mediaOffsetSeconds
            ) * 1_000_000_000
        )
        return anchorNanoseconds + loopOffset + mediaOffset
    }

    /// Maps an audio sample offset to its host playback time.
    ///
    /// - Parameters:
    ///   - loopIndex: The zero-based playback cycle.
    ///   - sampleOffset: The audio sample offset within this cycle.
    ///
    /// - Returns: The monotonic host timestamp, in nanoseconds.
    func target(
        loopIndex: Int,
        sampleOffset: Int
    ) -> UInt64 {
        target(
            loopIndex: loopIndex,
            mediaOffsetSeconds: Double(sampleOffset) / Double(AudioFrame.sampleRate)
        )
    }
}
