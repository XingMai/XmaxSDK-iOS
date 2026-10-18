//
//  MediaPlaybackTimeline.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 为同一文件的音频和视频提供统一的循环播放时钟。
struct MediaPlaybackTimeline: Sendable {

    /// 播放时钟
    let anchorNanoseconds: UInt64
    let cycleSampleCount: Int
    let cycleDurationNanoseconds: UInt64

    /// 创建以完整 PCM 包对齐循环时长的音视频播放时钟。
    ///
    /// - Parameter mediaDurationSeconds: 已校验为正有限值的文件时长，单位为秒。
    init(mediaDurationSeconds: Double) {
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
            Double(cycleSampleCount) /
                Double(AudioFrame.sampleRate) * 1_000_000_000
        )
        anchorNanoseconds = DispatchTime.now().uptimeNanoseconds + 100_000_000
    }

    /// 将媒体时间偏移映射到主机播放时刻。
    ///
    /// - Parameters:
    ///   - loopIndex: 从零开始的循环轮次。
    ///   - mediaOffsetSeconds: 当前轮次内的媒体偏移，单位为秒。
    /// - Returns: 对应主机单调时钟的纳秒时间戳。
    func target(
        loopIndex: Int,
        mediaOffsetSeconds: Double
    ) -> UInt64 {
        let loopOffset = cycleDurationNanoseconds * UInt64(loopIndex)
        let mediaOffset = UInt64(
            max(0, mediaOffsetSeconds) * 1_000_000_000
        )
        return anchorNanoseconds + loopOffset + mediaOffset
    }

    /// 将音频采样偏移映射到主机播放时刻。
    ///
    /// - Parameters:
    ///   - loopIndex: 从零开始的循环轮次。
    ///   - sampleOffset: 当前轮次内的音频采样偏移。
    /// - Returns: 对应主机单调时钟的纳秒时间戳。
    func target(
        loopIndex: Int,
        sampleOffset: Int
    ) -> UInt64 {
        target(
            loopIndex: loopIndex,
            mediaOffsetSeconds: Double(sampleOffset) /
                Double(AudioFrame.sampleRate)
        )
    }
}
