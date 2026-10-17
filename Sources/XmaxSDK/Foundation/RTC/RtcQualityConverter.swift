//
//  RtcQualityConverter.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AgoraRtcKit

/// 在声网质量事件与中性质量模型之间转换。
enum RtcQualityConverter {
    static func uplinkVideoStatistics(_ stats: AgoraRtcLocalVideoStats) -> UplinkVideoStatistics {
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

    static func downlinkVideoStatistics(
        userID: String, _ stats: AgoraRtcRemoteVideoStats
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

    private static func nonnegative(_ value: Int) -> Int? {
        value >= 0 ? value : nil
    }

    static func convertLevel(_ quality: AgoraNetworkQuality) -> RtcQualityLevel {
        RtcQualityLevel(rawValue: Int(quality.rawValue)) ?? .unknown
    }
}
