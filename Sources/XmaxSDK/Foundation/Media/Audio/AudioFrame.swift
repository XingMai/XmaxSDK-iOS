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

/// RTC 外部音频链路使用的 48 kHz 单声道 PCM 音频帧。
struct AudioFrame: Equatable, Sendable {

    /// PCM 采样率，固定为 48000 Hz。
    static let sampleRate = 48_000

    /// PCM 声道数，固定为单声道。
    static let channelCount = 1

    /// 每帧采样数；48 kHz 下对应 10 ms。
    static let samplesPerFrame = 480

    /// 48 kHz 单声道 PCM16 音频数据。
    let data: Data

    /// 音频帧在统一播放时间轴上的时间戳，单位为微秒。
    let timestampUs: Int64
}
