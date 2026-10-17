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

    // 自动调档
    private var uplinkQuality: QualityDirection?
    private var downlinkQuality: QualityDirection?
    private var history: QualityHistory?
    private var adaptiveListener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?
    private let historyDefaults: UserDefaults

    init(rtcManager: any RtcManaging, historyDefaults: UserDefaults = .standard) {
        self.historyDefaults = historyDefaults
        rtcManager.setQualityListener(self)
    }

    var qualityConfiguration: QualityConfiguration? {
        listenerLock.withLock { configuration() }
    }

    func prepareQuality(baseline: RealtimeVideoFormat, model: String) -> QualityConfiguration {
        listenerLock.withLock {
            let history = QualityHistory(model: model, defaults: historyDefaults)
            self.history = history
            uplinkQuality = QualityDirection(baseline: baseline, level: history.read(downlink: false), downlink: false)
            downlinkQuality = QualityDirection(baseline: baseline, level: history.read(downlink: true), downlink: true)
            return configuration()!
        }
    }

    func setAdaptiveQualityListener(_ listener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?) {
        listenerLock.withLock { adaptiveListener = listener }
    }

    func proposeQuality(_ quality: RealtimeNetworkQuality, sampledAt: TimeInterval) -> QualityChange {
        listenerLock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            return QualityChange(
                uplink: uplinkQuality?.observe(quality.uplink, sampledAt: sampledAt, now: now),
                downlink: downlinkQuality?.observe(quality.downlink, sampledAt: sampledAt, now: now)
            )
        }
    }

    func completeQuality(downlink: Bool, level: Int, success: Bool) {
        listenerLock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            if downlink {
                downlinkQuality?.complete(level: level, success: success, now: now)
            } else {
                uplinkQuality?.complete(level: level, success: success, now: now)
            }
            if success { history?.write(level: level, downlink: downlink) }
        }
    }

    func resetQualitySamples() {
        listenerLock.withLock {
            uplinkQuality?.resetSamples()
            downlinkQuality?.resetSamples()
        }
    }

    func resetQuality() {
        listenerLock.withLock {
            uplinkQuality = nil
            downlinkQuality = nil
            history = nil
            adaptiveListener = nil
        }
    }

    private func configuration() -> QualityConfiguration? {
        guard let uplinkQuality, let downlinkQuality else { return nil }
        return QualityConfiguration(baseline: uplinkQuality.baseline, uplinkLevel: uplinkQuality.level, downlinkLevel: downlinkQuality.level)
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
        let quality = RealtimeNetworkQuality(
            uplink: Self.networkQualityLevel(uplink),
            downlink: Self.networkQualityLevel(downlink)
        )
        let adaptive = listenerLock.withLock { adaptiveListener }
        adaptive?(quality, ProcessInfo.processInfo.systemUptime)
        listener?(quality)
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
