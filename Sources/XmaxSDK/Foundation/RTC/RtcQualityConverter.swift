//
//  RtcQualityConverter.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AgoraRtcKit

/// 在声网质量事件与中性质量模型之间转换。
enum RtcQualityConverter {

    /// 将声网本地视频统计转换为 SDK 上行指标。
    ///
    /// - Parameter stats: 声网上行统计。
    /// - Returns: 无效指标使用 `nil` 表示的上行统计。
    static func uplinkVideoStatistics(
        _ stats: AgoraRtcLocalVideoStats
    ) -> UplinkVideoStatistics {
        UplinkVideoStatistics(
            width: stats.encodedFrameWidth > 0 ? stats.encodedFrameWidth : nil,
            height: stats.encodedFrameHeight > 0 ? stats.encodedFrameHeight : nil,
            captureFrameRate: nonnegative(stats.captureFrameRate),
            encodeFrameRate: nonnegative(stats.encoderOutputFrameRate),
            sendFrameRate: Int(exactly: stats.sentFrameRate),
            bitrateKbps: Int(exactly: stats.sentBitrate),
            packetLossPercent: (0...100).contains(stats.txPacketLossRate) ? stats.txPacketLossRate : nil
        )
    }

    /// 将声网远端视频统计转换为 SDK 下行指标。
    ///
    /// - Parameters:
    ///   - userID: 远端用户账号。
    ///   - stats: 声网下行统计。
    /// - Returns: 关联远端账号且无效指标为 `nil` 的下行统计。
    static func downlinkVideoStatistics(
        userID: String,
        _ stats: AgoraRtcRemoteVideoStats
    ) -> DownlinkVideoStatistics {
        DownlinkVideoStatistics(
            userID: userID,
            width: stats.width > 0 ? Int(exactly: stats.width) : nil,
            height: stats.height > 0 ? Int(exactly: stats.height) : nil,
            decodeFrameRate: nonnegative(stats.decoderOutputFrameRate),
            renderFrameRate: nonnegative(stats.rendererOutputFrameRate),
            bitrateKbps: Int(exactly: stats.receivedBitrate),
            packetLossPercent: (0...100).contains(stats.packetLossRate) ? stats.packetLossRate : nil,
            endToEndDelayMs: Int(exactly: stats.e2eDelay)
        )
    }

    /// 保留非负统计值并过滤无效负值。
    ///
    /// - Parameter value: 待校验的统计值。
    /// - Returns: 非负原值；负值返回 `nil`。
    private static func nonnegative(
        _ value: Int
    ) -> Int? {
        value >= 0 ? value : nil
    }

    /// 将声网网络质量转换为 SDK 质量等级。
    ///
    /// - Parameter quality: 声网网络质量等级。
    /// - Returns: 对应的 SDK 等级；未知值返回 `.unknown`。
    static func convertLevel(
        _ quality: AgoraNetworkQuality
    ) -> RtcQualityLevel {
        RtcQualityLevel(rawValue: Int(quality.rawValue)) ?? .unknown
    }
}
