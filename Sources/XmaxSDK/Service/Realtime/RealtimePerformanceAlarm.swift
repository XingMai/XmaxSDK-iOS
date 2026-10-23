//
//  RealtimePerformanceAlarm.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A realtime performance limitation state.
public enum RealtimePerformanceStatus: String, CaseIterable, Sendable {

    /// Device performance is limited; consider the suggested format.
    case limited = "Limited"

    /// Device performance has recovered.
    case recovered = "Recovered"
}

/// A realtime performance alarm.
public struct RealtimePerformanceAlarm: Equatable, Sendable {

    /// The current performance limitation or recovery state.
    public let status: RealtimePerformanceStatus

    /// The suggested RTC fallback format, or `nil` if its parameters are invalid.
    public let suggestedVideoFormat: RealtimeVideoFormat?

    /// Creates a performance alarm.
    public init(
        status: RealtimePerformanceStatus,
        suggestedVideoFormat: RealtimeVideoFormat?
    ) {
        self.status = status
        self.suggestedVideoFormat = suggestedVideoFormat
    }
}

/// A realtime performance alarm listener.
public typealias RealtimePerformanceAlarmListener =
    @MainActor @Sendable (
        RealtimePerformanceAlarm
    ) -> Void
