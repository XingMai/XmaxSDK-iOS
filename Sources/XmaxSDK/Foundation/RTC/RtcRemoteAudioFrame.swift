//
//  RtcRemoteAudioFrame.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Owned remote PCM with its unmodified native rendering clock, or an invalid-buffer marker.
struct RtcRemoteAudioFrame: Sendable {

    /// Copied interleaved signed 16-bit PCM bytes; empty data marks a rejected native buffer.
    let data: Data

    /// Samples per second in each channel.
    let sampleRate: Int

    /// The number of interleaved channels.
    let channels: Int

    /// Samples per channel in this packet.
    let samplesPerChannel: Int

    /// The receiver rendering timestamp in milliseconds.
    let renderTimeMs: Int64
}

/// A synchronous receiver for an owned native audio packet.
typealias RtcRemoteAudioFrameListener = @Sendable (RtcRemoteAudioFrame) -> Void
