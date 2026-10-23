//
//  VideoStatistics.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Uplink video statistics. Unavailable metrics are `nil`.
public struct UplinkVideoStatistics: Equatable, Sendable {

    /// The encoded width, in pixels.
    public let width: Int?

    /// The encoded height, in pixels.
    public let height: Int?

    /// The measured capture frame rate, in frames per second.
    public let captureFrameRate: Int?

    /// The measured encoding frame rate, in frames per second.
    public let encodeFrameRate: Int?

    /// The measured sending frame rate, in frames per second.
    public let sendFrameRate: Int?

    /// The sending bitrate, in kbps.
    public let bitrateKbps: Int?

    /// Packet loss between the local device and RTC service, from 0 to 100 percent.
    public let packetLossPercent: Int?

    /// Creates video statistics.
    public init(
        width: Int? = nil,
        height: Int? = nil,
        captureFrameRate: Int? = nil,
        encodeFrameRate: Int? = nil,
        sendFrameRate: Int? = nil,
        bitrateKbps: Int? = nil,
        packetLossPercent: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.captureFrameRate = captureFrameRate
        self.encodeFrameRate = encodeFrameRate
        self.sendFrameRate = sendFrameRate
        self.bitrateKbps = bitrateKbps
        self.packetLossPercent = packetLossPercent
    }
}

/// Downlink video statistics. Unavailable metrics are `nil`.
public struct DownlinkVideoStatistics: Equatable, Sendable {

    /// The remote user identifier.
    public let userID: String

    /// The received width, in pixels.
    public let width: Int?

    /// The received height, in pixels.
    public let height: Int?

    /// The decoding frame rate, in frames per second.
    public let decodeFrameRate: Int?

    /// The RTC rendering frame rate, excluding SDK interpolation.
    public let renderFrameRate: Int?

    /// The receiving bitrate, in kbps.
    public let bitrateKbps: Int?

    /// The downlink packet loss, from 0 to 100 percent.
    public let packetLossPercent: Int?

    /// The RTC media end-to-end latency, in milliseconds, excluding complete AI generation time.
    public let endToEndDelayMs: Int?

    /// Creates video statistics.
    public init(
        userID: String,
        width: Int? = nil,
        height: Int? = nil,
        decodeFrameRate: Int? = nil,
        renderFrameRate: Int? = nil,
        bitrateKbps: Int? = nil,
        packetLossPercent: Int? = nil,
        endToEndDelayMs: Int? = nil
    ) {
        self.userID = userID
        self.width = width
        self.height = height
        self.decodeFrameRate = decodeFrameRate
        self.renderFrameRate = renderFrameRate
        self.bitrateKbps = bitrateKbps
        self.packetLossPercent = packetLossPercent
        self.endToEndDelayMs = endToEndDelayMs
    }
}

/// A main-actor uplink statistics handler receiving `nil` when unpublished or disconnected.
public typealias UplinkVideoStatisticsListener =
    @MainActor @Sendable (UplinkVideoStatistics?) -> Void

/// A main-actor downlink statistics handler receiving `nil` when cleared or disconnected.
public typealias DownlinkVideoStatisticsListener =
    @MainActor @Sendable (DownlinkVideoStatistics?) -> Void
