//
//  AudioFrame.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// RTC 外部音频链路使用的 48 kHz 单声道 PCM 音频帧。
struct AudioFrame: Equatable, Sendable {

    // 音频格式
    static let sampleRate = 48_000
    static let channelCount = 1
    static let samplesPerFrame = 480

    // 帧数据
    let data: Data
    let timestampUs: Int64
}
