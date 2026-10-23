//
//  RealtimeNetworkQuality.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// An RTC network quality rating.
public enum RealtimeNetworkQualityLevel: String, CaseIterable, Sendable {

    /// RTC has not supplied a valid quality rating.
    case unknown = "Unknown"

    /// Excellent network quality.
    case excellent = "Excellent"

    /// Good network quality.
    case good = "Good"

    /// Poor quality that may affect realtime playback.
    case poor = "Poor"

    /// Very poor quality affecting realtime playback.
    case bad = "Bad"

    /// Extremely poor quality that may severely interrupt media.
    case veryBad = "VeryBad"

    /// The network connection is disconnected.
    case down = "Down"
}

/// The uplink and downlink quality of a realtime session.
public struct RealtimeNetworkQuality: Equatable, Sendable {

    /// The network quality sending local media to the RTC room.
    public let uplink: RealtimeNetworkQualityLevel

    /// The network quality receiving media from the RTC room.
    public let downlink: RealtimeNetworkQualityLevel

    /// Creates a network quality snapshot.
    public init(
        uplink: RealtimeNetworkQualityLevel,
        downlink: RealtimeNetworkQualityLevel
    ) {
        self.uplink = uplink
        self.downlink = downlink
    }
}

/// A realtime network quality listener.
public typealias RealtimeNetworkQualityListener =
    @MainActor @Sendable (
        RealtimeNetworkQuality
    ) -> Void
