//
//  RealtimePerformanceAlarm.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 实时性能限制状态。
public enum RealtimePerformanceStatus: String, CaseIterable, Sendable {

    /// 设备性能受限，接入方应考虑使用建议的视频格式。
    case limited = "Limited"

    /// 设备性能已经恢复。
    case recovered = "Recovered"
}

/// 实时性能告警信息。
public struct RealtimePerformanceAlarm: Equatable, Sendable {

    /// 当前设备性能是受限还是已经恢复。
    public let status: RealtimePerformanceStatus

    /// RTC 建议的降级视频格式；建议参数无效时为空。
    public let suggestedVideoFormat: RealtimeVideoFormat?

    /// 创建实时性能告警信息。
    ///
    /// - Parameters:
    ///   - status: 设备当前的性能限制状态。
    ///   - suggestedVideoFormat: 建议采用的视频规格；没有有效建议时传入 `nil`。
    public init(
        status: RealtimePerformanceStatus,
        suggestedVideoFormat: RealtimeVideoFormat?
    ) {
        self.status = status
        self.suggestedVideoFormat = suggestedVideoFormat
    }
}

/// 实时性能告警监听器。
public typealias RealtimePerformanceAlarmListener = @MainActor @Sendable (
    RealtimePerformanceAlarm
) -> Void
