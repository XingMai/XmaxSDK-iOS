//
//  RemoteAudioTimeline.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia

/// Advances audio by exact sample durations, retaining its offset from the video rendering clock.
struct RemoteAudioTimeline {

    /// The largest tolerated difference between sample time and the native render clock.
    private let maximumClockDifference = CMTime(
        value: 100,
        timescale: 1_000
    )

    /// The next continuous packet time.
    private var nextPTS: CMTime?

    /// The current packet format.
    private var format: [Int]?

    /// Clears sample continuity after listener or stream replacement.
    mutating func reset() {
        nextPTS = nil
        format = nil
    }

    /// Resolves a packet or rejects an unusable native timestamp or PCM layout.
    ///
    /// Native render times can repeat for batched packets. Differences over 100 ms and format
    /// changes re-anchor at the native clock and explicitly break continuity instead of hiding gaps.
    ///
    /// - Parameter frame: The remote PCM packet and its native rendering timestamp.
    ///
    /// - Returns: The timestamped audio frame and continuity flag, or `nil` for an invalid packet.
    mutating func resolve(
        _ frame: RtcRemoteAudioFrame
    ) -> (frame: RealtimeAudioFrame, discontinuous: Bool)? {
        guard frame.renderTimeMs > 0,
            (8_000...192_000).contains(frame.sampleRate),
            (1...2).contains(frame.channels),
            (1...192_000).contains(frame.samplesPerChannel),
            frame.data.count == frame.samplesPerChannel * frame.channels * 2
        else {
            reset()
            return nil
        }

        let nativePTS = CMTime(
            value: frame.renderTimeMs,
            timescale: 1_000
        )
        let currentFormat = [frame.sampleRate, frame.channels]
        var discontinuous = nextPTS == nil || format != currentFormat
        var pts = nextPTS ?? nativePTS
        if format != currentFormat {
            pts = nativePTS
        } else if let nextPTS {
            let difference = CMTimeAbsoluteValue(
                CMTimeSubtract(
                    nativePTS,
                    nextPTS
                )
            )
            if difference > maximumClockDifference {
                pts = nativePTS
                discontinuous = true
            }
        }
        let output = RealtimeAudioFrame(
            data: frame.data,
            sampleRate: frame.sampleRate,
            channels: frame.channels,
            samplesPerChannel: frame.samplesPerChannel,
            presentationTimeStamp: pts
        )
        nextPTS = CMTimeAdd(
            pts,
            output.duration
        )
        format = currentFormat
        return (output, discontinuous)
    }
}
