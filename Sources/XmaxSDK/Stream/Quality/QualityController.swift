import Foundation

/// 转换 RTC 质量事件并通知实时生成业务监听器。
final class QualityController: QualityControlling, RtcQualityListener,
    @unchecked Sendable {

    // 并发控制
    private let listenerLock = NSLock()

    // 事件监听
    private var networkQualityListener: RealtimeNetworkQualityListener?
    private var performanceAlarmListener: RealtimePerformanceAlarmListener?
    private var uplinkStatisticsListener: UplinkVideoStatisticsListener?
    private var downlinkStatisticsListener: DownlinkVideoStatisticsListener?

    // 统计生命周期
    private var uplinkStatisticsEnabled = false
    private var downlinkStatisticsUser: String?
    private var uplinkStatisticsVersion = 0
    private var downlinkStatisticsVersion = 0

    init(rtcManager: any RtcManaging) {
        rtcManager.setQualityListener(self)
    }

    func setUplinkVideoStatisticsListener(_ listener: UplinkVideoStatisticsListener?) {
        listenerLock.withLock {
            uplinkStatisticsVersion &+= 1
            uplinkStatisticsListener = listener
        }
    }

    func setDownlinkVideoStatisticsListener(_ listener: DownlinkVideoStatisticsListener?) {
        listenerLock.withLock {
            downlinkStatisticsVersion &+= 1
            downlinkStatisticsListener = listener
        }
    }

    func setUplinkVideoStatisticsEnabled(_ enabled: Bool) {
        let version = listenerLock.withLock {
            uplinkStatisticsVersion &+= 1
            uplinkStatisticsEnabled = enabled
            return uplinkStatisticsVersion
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let listener = listenerLock.withLock {
                uplinkStatisticsVersion == version ? uplinkStatisticsListener : nil
            }
            listener?(nil)
        }
    }

    func setDownlinkVideoStatisticsUser(_ userID: String?) {
        let version = listenerLock.withLock {
            downlinkStatisticsVersion &+= 1
            downlinkStatisticsUser = userID
            return downlinkStatisticsVersion
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let listener = listenerLock.withLock {
                downlinkStatisticsVersion == version ? downlinkStatisticsListener : nil
            }
            listener?(nil)
        }
    }

    @MainActor
    func onUplinkVideoStatistics(_ statistics: UplinkVideoStatistics) {
        let listener = listenerLock.withLock {
            uplinkStatisticsEnabled ? uplinkStatisticsListener : nil
        }
        listener?(statistics)
    }

    @MainActor
    func onDownlinkVideoStatistics(_ statistics: DownlinkVideoStatistics) {
        let listener = listenerLock.withLock {
            statistics.userID == downlinkStatisticsUser ? downlinkStatisticsListener : nil
        }
        listener?(statistics)
    }

    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) {
        listenerLock.withLock {
            networkQualityListener = listener
        }
    }

    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) {
        listenerLock.withLock {
            performanceAlarmListener = listener
        }
    }

    @MainActor
    func onNetworkQuality(
        uplink: RtcQualityLevel,
        downlink: RtcQualityLevel
    ) {
        let listener = listenerLock.withLock { networkQualityListener }
        listener?(
            RealtimeNetworkQuality(
                uplink: Self.networkQualityLevel(uplink),
                downlink: Self.networkQualityLevel(downlink)
            )
        )
    }

    @MainActor
    func onPerformanceAlarm(
        limited: Bool,
        suggestedWidth: Int,
        suggestedHeight: Int,
        suggestedFrameRate: Int
    ) {
        let listener = listenerLock.withLock { performanceAlarmListener }
        listener?(
            RealtimePerformanceAlarm(
                status: limited ? .limited : .recovered,
                suggestedVideoFormat: Self.suggestedVideoFormat(
                    width: suggestedWidth,
                    height: suggestedHeight,
                    frameRate: suggestedFrameRate
                )
            )
        )
    }
}

private extension QualityController {
    static func networkQualityLevel(
        _ level: RtcQualityLevel
    ) -> RealtimeNetworkQualityLevel {
        switch level {
        case .unknown:
            .unknown
        case .excellent:
            .excellent
        case .good:
            .good
        case .poor:
            .poor
        case .bad:
            .bad
        case .veryBad:
            .veryBad
        case .down:
            .down
        }
    }

    static func suggestedVideoFormat(
        width: Int,
        height: Int,
        frameRate: Int
    ) -> RealtimeVideoFormat? {
        guard width > 0, height > 0, frameRate > 0 else {
            return nil
        }
        return RealtimeVideoFormat(
            width: width,
            height: height,
            fps: frameRate
        )
    }
}
