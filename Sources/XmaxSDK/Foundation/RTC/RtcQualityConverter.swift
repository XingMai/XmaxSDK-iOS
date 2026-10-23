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

/// Converts Agora quality events to SDK metrics.
enum RtcQualityConverter {

    /// Converts Agora local video statistics to uplink metrics.
    ///
    /// - Parameter stats: The Agora uplink statistics.
    ///
    /// - Returns: The uplink metrics, with invalid values represented by `nil`.
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
            packetLossPercent: (0...100).contains(stats.txPacketLossRate)
                ? stats.txPacketLossRate : nil
        )
    }

    /// Converts Agora remote statistics to downlink metrics.
    ///
    /// - Parameters:
    ///   - userID: The remote user account.
    ///   - stats: The Agora downlink statistics.
    ///
    /// - Returns: The downlink metrics for the remote account, with invalid values represented by
    ///   `nil`.
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
            packetLossPercent: (0...100).contains(stats.packetLossRate)
                ? stats.packetLossRate : nil,
            endToEndDelayMs: Int(exactly: stats.e2eDelay)
        )
    }

    /// Filters invalid negative statistics.
    ///
    /// - Parameter value: The statistic to validate.
    ///
    /// - Returns: The nonnegative value, or `nil` if negative.
    private static func nonnegative(
        _ value: Int
    ) -> Int? {
        value >= 0 ? value : nil
    }

    /// Converts Agora network quality to an SDK rating.
    ///
    /// - Parameter quality: The Agora network quality.
    ///
    /// - Returns: The SDK rating, or `.unknown` for unrecognized values.
    static func convertLevel(
        _ quality: AgoraNetworkQuality
    ) -> RtcQualityLevel {
        RtcQualityLevel(rawValue: Int(quality.rawValue)) ?? .unknown
    }
}
