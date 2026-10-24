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

    /// Creates an observer whose provider filters packets before bytes are copied.
    init(
        listenerProvider: @escaping @Sendable (UInt, String) -> RtcRemoteAudioFrameListener?
    ) {
        self.listenerProvider = listenerProvider
    }

    /// Observes individual remote audio before mixing.
    func getObservedAudioFramePosition() -> AgoraAudioFramePosition {
        .beforeMixing
    }

    /// Copies a remote user's audio without changing RTC playback or mixing local input.
    ///
    /// - Parameters:
    ///   - frame: The PCM frame borrowed from Agora for this callback.
    ///   - channelId: The room identifier associated with the frame.
    ///   - uid: The remote user identifier.
    ///
    /// - Returns: `true` to preserve native audio playback.
    func onPlaybackAudioFrame(
        beforeMixing frame: AgoraAudioFrame,
        channelId: String,
        uid: UInt
    ) -> Bool {
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

    /// Validates and owns callback-borrowed bytes before asynchronous delivery.
    ///
    /// - Parameters:
    ///   - buffer: The borrowed interleaved PCM bytes.
    ///   - channelID: The room identifier associated with the frame.
    ///   - uid: The remote user identifier.
    ///   - samplesPerChannel: The number of samples in each channel.
    ///   - sampleRate: The audio sample rate, in hertz.
    ///   - channels: The number of interleaved channels.
    ///   - bytesPerSample: The number of bytes per sample; only 16-bit PCM is accepted.
    ///   - renderTimeMs: The native rendering timestamp, in milliseconds.
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
        guard let listener = listenerProvider(
            uid,
            channelID
        ) else {
            return
        }

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
