//
//  AudioFrame.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A 48 kHz mono PCM frame for external RTC audio input.
struct AudioFrame: Equatable, Sendable {

    /// The sample rate, fixed at 48000 Hz.
    static let sampleRate = 48_000

    /// The channel count, fixed at one.
    static let channelCount = 1

    /// The samples per frame, representing 10 ms at 48 kHz.
    static let samplesPerFrame = 480

    /// The 48 kHz mono PCM16 data.
    let data: Data

    /// The timestamp on the shared playback timeline, in microseconds.
    let timestampUs: Int64
}
