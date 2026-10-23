//
//  RtcRemoteAudioSink.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AgoraRtcKit
import Foundation

/// Copies individual remote users' PCM while native callback storage is valid.
final class RtcRemoteAudioSink: NSObject, AgoraAudioFrameDelegate, @unchecked Sendable {

    /// Resolves the listener only for a current room and subscribed result user.
    private let listenerProvider: @Sendable (UInt, String) -> RtcRemoteAudioFrameListener?

    #if DEBUG
    /// The optional diagnostic taps, forwarded through the engine's single audio delegate.
    private let diagnosticSink: RtcDebugAudioSink
    #endif

    /// Creates an observer whose provider filters packets before bytes are copied.
    init(
        roomID: String,
        listenerProvider: @escaping @Sendable (UInt, String) -> RtcRemoteAudioFrameListener?
    ) {
        self.listenerProvider = listenerProvider
        #if DEBUG
        diagnosticSink = RtcDebugAudioSink(roomID: roomID)
        #endif
    }

    /// Observes individual remote audio; Debug builds also retain the diagnostic playback tap.
    func getObservedAudioFramePosition() -> AgoraAudioFramePosition {
        #if DEBUG
        [.beforeMixing, .playback]
        #else
        .beforeMixing
        #endif
    }

    /// Copies a remote user's audio without changing RTC playback or mixing local input.
    func onPlaybackAudioFrame(
        beforeMixing frame: AgoraAudioFrame,
        channelId: String,
        uid: UInt
    ) -> Bool {
        #if DEBUG
        _ = diagnosticSink.onPlaybackAudioFrame(
            beforeMixing: frame,
            channelId: channelId,
            uid: uid
        )
        #endif
        capturePCM(
            frame.buffer,
            channelID: channelId,
            uid: uid,
            samplesPerChannel: frame.samplesPerChannel,
            sampleRate: frame.samplesPerSec,
            channels: frame.channels,
            bytesPerSample: frame.bytesPerSample,
            renderTimeMs: frame.renderTimeMs
        )
        return true
    }

    #if DEBUG
    /// Keeps aggregate remote playback exclusively in the opt-in debug recorder.
    func onPlaybackAudioFrame(
        _ frame: AgoraAudioFrame,
        channelId: String
    ) -> Bool {
        diagnosticSink.onPlaybackAudioFrame(
            frame,
            channelId: channelId
        )
    }
    #endif

    /// Validates and owns callback-borrowed bytes before asynchronous delivery.
    func capturePCM(
        _ buffer: UnsafeRawPointer?,
        channelID: String,
        uid: UInt,
        samplesPerChannel: Int,
        sampleRate: Int,
        channels: Int,
        bytesPerSample: Int,
        renderTimeMs: Int64
    ) {
        guard let listener = listenerProvider(uid, channelID) else { return }
        guard let buffer,
              bytesPerSample == 2,
              (8_000...192_000).contains(sampleRate),
              (1...2).contains(channels),
              (1...192_000).contains(samplesPerChannel)
        else {
            listener(
                RtcRemoteAudioFrame(
                    data: Data(),
                    sampleRate: sampleRate,
                    channels: channels,
                    samplesPerChannel: samplesPerChannel,
                    renderTimeMs: renderTimeMs
                )
            )
            return
        }
        listener(
            RtcRemoteAudioFrame(
                data: Data(
                    bytes: buffer,
                    count: samplesPerChannel * channels * bytesPerSample
                ),
                sampleRate: sampleRate,
                channels: channels,
                samplesPerChannel: samplesPerChannel,
                renderTimeMs: renderTimeMs
            )
        )
    }
}
