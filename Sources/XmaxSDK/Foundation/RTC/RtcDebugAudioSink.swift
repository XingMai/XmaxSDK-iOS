//
//  RtcDebugAudioSink.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#if DEBUG
@preconcurrency import AgoraRtcKit
import Foundation

/// Observes remote PCM before mixing and at playback, copying bytes only during an opt-in capture.
final class RtcDebugAudioSink: NSObject, AgoraAudioFrameDelegate, @unchecked Sendable {

    /// The room whose native callbacks may be recorded.
    private let roomID: String

    /// Creates a room-scoped, read-only audio observer.
    init(
        roomID: String
    ) {
        self.roomID = roomID
    }

    /// Requests individual remote audio and a separate aggregate remote-playback diagnostic tap.
    func getObservedAudioFramePosition() -> AgoraAudioFramePosition {
        [.beforeMixing, .playback]
    }

    /// Observes aggregate remote playback separately from individual users' pre-mix packets.
    func onPlaybackAudioFrame(
        _ frame: AgoraAudioFrame,
        channelId: String
    ) -> Bool {
        capturePCM(
            frame.buffer,
            channelId: channelId,
            uid: 0,
            samplesPerChannel: frame.samplesPerChannel,
            sampleRate: frame.samplesPerSec,
            channels: frame.channels,
            bytesPerSample: frame.bytesPerSample,
            renderTimeMs: frame.renderTimeMs,
            presentationMs: frame.presentationMs,
            rtpTimestamp: frame.rtpTimestamp,
            avSyncType: frame.avSyncType,
            tap: "playback_mixed"
        )
        return true
    }

    /// Copies native callback bytes and preserves all candidate media clocks without normalization.
    func onPlaybackAudioFrame(
        beforeMixing frame: AgoraAudioFrame,
        channelId: String,
        uid: UInt
    ) -> Bool {
        capturePCM(
            frame.buffer,
            channelId: channelId,
            uid: uid,
            samplesPerChannel: frame.samplesPerChannel,
            sampleRate: frame.samplesPerSec,
            channels: frame.channels,
            bytesPerSample: frame.bytesPerSample,
            renderTimeMs: frame.renderTimeMs,
            presentationMs: frame.presentationMs,
            rtpTimestamp: frame.rtpTimestamp,
            avSyncType: frame.avSyncType
        )
        return true
    }

    /// Copies a callback-borrowed PCM buffer synchronously, preserving its supplied format and clocks.
    ///
    /// The pointer is used only during this call. The native wrapper is deliberately not retained:
    /// its backing storage belongs to Agora and cannot be constructed by an integrating app.
    func capturePCM(
        _ buffer: UnsafeRawPointer?,
        channelId: String,
        uid: UInt,
        samplesPerChannel: Int,
        sampleRate: Int,
        channels: Int,
        bytesPerSample: Int,
        renderTimeMs: Int64,
        presentationMs: Int64,
        rtpTimestamp: UInt32,
        avSyncType: Int,
        tap: String = "before_mixing"
    ) {
        let capture = RealtimeDebugCaptureBridge.shared
        guard capture.isRecording else { return }
        let host = DispatchTime.now().uptimeNanoseconds
        // Aggregate playback may omit a channel; this observer owns the engine's sole SDK room.
        let aggregateWithoutChannel = tap == "playback_mixed" && channelId.isEmpty
        capture.event(
            "audio_callback_seen",
            roomID: roomID,
            fields: [
                "tap": tap,
                "uid": String(uid),
                "channel_matches": String(channelId == roomID),
                "channel_empty": String(channelId.isEmpty),
                "attributed_to_owned_room": String(aggregateWithoutChannel),
                "has_buffer": String(buffer != nil),
                "samples_per_channel": String(samplesPerChannel)
            ]
        )
        guard channelId == roomID || aggregateWithoutChannel else { return }
        guard samplesPerChannel > 0, samplesPerChannel <= 192_000,
              channels > 0, channels <= 8,
              bytesPerSample > 0, bytesPerSample <= 8,
              let buffer else {
            capture.event("invalid_audio_buffer", roomID: roomID, fields: ["uid": String(uid)])
            return
        }
        let count = samplesPerChannel * channels * bytesPerSample
        capture.audio(
            roomID: roomID,
            uid: uid,
            data: Data(bytes: buffer, count: count),
            fields: [
                "host_ns": String(host),
                "tap": tap,
                "render_ms": String(renderTimeMs),
                "presentation_ms": String(presentationMs),
                "rtp_timestamp": String(rtpTimestamp),
                "sample_rate": String(sampleRate),
                "samples_per_channel": String(samplesPerChannel),
                "channels": String(channels),
                "bytes_per_sample": String(bytesPerSample),
                "av_sync_type": String(avSyncType)
            ]
        )
    }
}
#endif
