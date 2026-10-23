//
//  RealtimeMediaFrame.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import Foundation

/// An owned packet of signed, little-endian, interleaved 16-bit remote PCM.
public struct RealtimeAudioFrame: Sendable {

    /// The copied PCM bytes, safe to retain after the callback returns.
    public let data: Data

    /// The number of samples per second in each channel.
    public let sampleRate: Int

    /// The number of interleaved audio channels.
    public let channels: Int

    /// The number of samples in each channel of this packet.
    public let samplesPerChannel: Int

    /// The first sample's time on the same receiver rendering timeline as remote video.
    ///
    /// Within a continuous run, time advances by the exact number of samples, even when native
    /// callbacks arrive in batches. This is a rendering timeline, not the source file's timecode.
    public let presentationTimeStamp: CMTime

    /// The exact packet duration, calculated from its sample count and sample rate.
    public var duration: CMTime {
        CMTime(
            value: Int64(samplesPerChannel),
            timescale: Int32(sampleRate)
        )
    }

    /// Creates an owned audio packet with a resolved presentation time.
    init(
        data: Data,
        sampleRate: Int,
        channels: Int,
        samplesPerChannel: Int,
        presentationTimeStamp: CMTime
    ) {
        self.data = data
        self.sampleRate = sampleRate
        self.channels = channels
        self.samplesPerChannel = samplesPerChannel
        self.presentationTimeStamp = presentationTimeStamp
    }
}

/// One remote audio or processed video packet, with a shared stream identity and time basis.
///
/// Events are serialized in delivery order, not sorted by presentation time across tracks. Video
/// processing can delay delivery relative to audio. Buffer and schedule both tracks by their PTS;
/// use one recording origin for both. An event does not represent an audio/video pair.
/// Treat video pixel buffers as read-only: rendering and the video-only listener may share them.
public struct RealtimeMediaFrame: Sendable {

    /// The media carried by an output event.
    public enum Content: Sendable {

        /// PCM belonging to the result stream's remote user, before remote-user mixing.
        case audio(RealtimeAudioFrame)

        /// A remote video frame after optional interpolation.
        case video(RealtimeVideoFrame)
    }

    /// An opaque identity shared by both tracks for one result-stream binding.
    ///
    /// A replacement stream or reconnection receives a new identity, even if RTC user IDs repeat.
    public let streamID: UUID

    /// Whether this track begins a run, changes format or clock, or follows discarded output.
    ///
    /// The first event of each track is marked. Later discontinuities require your app to handle
    /// the gap or start a new recording segment. Output-queue loss does not compress the timeline.
    public let isDiscontinuous: Bool

    /// The audio packet or processed video frame.
    public let content: Content

    /// The packet's presentation time, which does not necessarily start at zero.
    public var presentationTimeStamp: CMTime {
        switch content {
        case .audio(let frame): frame.presentationTimeStamp
        case .video(let frame): frame.presentationTimeStamp
        }
    }

    /// The audio duration or suggested video duration; video duration may be `.invalid`.
    public var duration: CMTime {
        switch content {
        case .audio(let frame): frame.duration
        case .video(let frame): frame.duration
        }
    }

    /// Creates a remote output event.
    init(
        streamID: UUID,
        isDiscontinuous: Bool,
        content: Content
    ) {
        self.streamID = streamID
        self.isDiscontinuous = isDiscontinuous
        self.content = content
    }
}

/// A serialized background handler for remote PCM and processed video output.
public typealias RealtimeMediaFrameListener = @Sendable (RealtimeMediaFrame) -> Void
