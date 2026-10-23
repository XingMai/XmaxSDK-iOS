//
//  QualityControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for quality and performance alarms.
protocol QualityControlling: Sendable {

    /// The connection quality configuration, if prepared.
    var qualityConfiguration: QualityConfiguration? {
        get
    }

    /// Prepares initial transport quality from the media baseline and model history.
    ///
    /// - Parameters:
    ///   - baseline: The resolved local media baseline, unchanged by adaptation.
    ///   - model: The model identifier isolating quality history.
    ///   - minimumInputPixels: The model's minimum uplink area, in pixels.
    ///   - isAdaptiveQualityEnabled: Whether to adapt quality. Disabled connections start at L1
    ///     without using history.
    ///
    /// - Returns: The initial directional quality configuration.
    func prepareQuality(
        baseline: RealtimeVideoFormat,
        model: String,
        minimumInputPixels: Int,
        isAdaptiveQualityEnabled: Bool
    ) -> QualityConfiguration

    /// Sets the internal adaptation listener independently of your app's network listener.
    ///
    /// - Parameter listener: The quality and monotonic sample time handler, or `nil` to remove it.
    func setAdaptiveQualityListener(
        _ listener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?
    )

    /// Proposes quality levels without committing them.
    ///
    /// - Parameters:
    ///   - quality: The current directional network quality.
    ///   - sampledAt: The monotonic sample time, in seconds.
    ///
    /// - Returns: The candidate levels satisfying sample and cooldown requirements.
    func proposeQuality(
        _ quality: RealtimeNetworkQuality,
        sampledAt: TimeInterval
    ) -> QualityChange

    /// Commits an adjustment result, persisting successful levels only.
    ///
    /// - Parameters:
    ///   - downlink: Whether this is downlink rather than uplink.
    ///   - level: The attempted quality level.
    ///   - success: Whether configuration succeeded.
    func completeQuality(
        downlink: Bool,
        level: RealtimeQualityLevel,
        success: Bool
    )

    /// Clears consecutive samples collected while adaptation was unavailable.
    func resetQualitySamples()

    /// Releases connection quality state and its internal sample listener.
    func resetQuality()

    /// Updates uplink statistics availability and clears previous statistics.
    ///
    /// - Parameter enabled: Whether local video is published.
    func setUplinkVideoStatisticsEnabled(
        _ enabled: Bool
    )

    /// Changes the downlink statistics target and clears previous statistics.
    ///
    /// - Parameter userID: The result user identifier, or `nil` to stop delivery.
    func setDownlinkVideoStatisticsUser(
        _ userID: String?
    )

    /// Sets the uplink video statistics listener.
    ///
    /// - Parameter listener: The main-actor handler, receiving `nil` when unpublished or
    ///   disconnected. Pass `nil` to remove it.
    func setUplinkVideoStatisticsListener(
        _ listener: UplinkVideoStatisticsListener?
    )

    /// Sets the downlink video statistics listener.
    ///
    /// - Parameter listener: The main-actor handler, receiving `nil` when the result stream clears.
    ///   Pass `nil` to remove it.
    func setDownlinkVideoStatisticsListener(
        _ listener: DownlinkVideoStatisticsListener?
    )

    /// Sets the network quality listener.
    ///
    /// - Parameter listener: The main-actor quality handler, or `nil` to remove it.
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    )

    /// Sets the device performance alarm listener.
    ///
    /// - Parameter listener: The main-actor performance handler, or `nil` to remove it.
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    )
}
