//
//  RtcQualityListener.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// An RTC network quality rating.
enum RtcQualityLevel: Int, CaseIterable, Sendable {

    /// No quality rating is available.
    case unknown

    /// Excellent network quality.
    case excellent

    /// Good network quality.
    case good

    /// Fair network quality.
    case poor

    /// Poor network quality.
    case bad

    /// Very poor network quality.
    case veryBad

    /// The network connection is unavailable.
    case down
}

/// A listener for RTC quality and performance fallback.
protocol RtcQualityListener: AnyObject {

    /// Receives local uplink video statistics.
    ///
    /// - Parameter statistics: The current uplink statistics.
    @MainActor
    func onUplinkVideoStatistics(
        _ statistics: UplinkVideoStatistics
    )

    /// Receives remote downlink video statistics.
    ///
    /// - Parameter statistics: The current downlink statistics.
    @MainActor
    func onDownlinkVideoStatistics(
        _ statistics: DownlinkVideoStatistics
    )

    /// Receives uplink and downlink network quality.
    ///
    /// - Parameters:
    ///   - uplink: The local sending direction's quality.
    ///   - downlink: The remote receiving direction's quality.
    @MainActor
    func onNetworkQuality(
        uplink: RtcQualityLevel,
        downlink: RtcQualityLevel
    )

    /// Receives performance limitation or recovery events.
    ///
    /// - Parameters:
    ///   - limited: Whether performance is currently limited.
    ///   - suggestedWidth: The suggested width, in pixels.
    ///   - suggestedHeight: The suggested height, in pixels.
    ///   - suggestedFrameRate: The suggested frame rate, in frames per second.
    @MainActor
    func onPerformanceAlarm(
        limited: Bool,
        suggestedWidth: Int,
        suggestedHeight: Int,
        suggestedFrameRate: Int
    )
}
