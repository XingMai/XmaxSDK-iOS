//
//  QualityController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 转换 RTC 质量事件并通知实时生成业务监听器。
final class QualityController: QualityControlling, RtcQualityListener,
    @unchecked Sendable {

    /// 保护质量监听器和统计有效期。
    private let listenerLock = NSLock()

    /// 接收上下行网络质量变化。
    private var networkQualityListener: RealtimeNetworkQualityListener?

    /// 接收本地编码性能告警。
    private var performanceAlarmListener: RealtimePerformanceAlarmListener?

    /// 接收上行视频统计。
    private var uplinkStatisticsListener: UplinkVideoStatisticsListener?

    /// 接收下行视频统计。
    private var downlinkStatisticsListener: DownlinkVideoStatisticsListener?

    /// 当前是否交付上行视频统计。
    private var uplinkStatisticsEnabled = false

    /// 当前下行统计所属的远端用户。
    private var downlinkStatisticsUser: String?

    /// 上行统计监听版本，用于过滤过期回调。
    private var uplinkStatisticsVersion = 0

    /// 下行统计监听版本，用于过滤过期回调。
    private var downlinkStatisticsVersion = 0

    /// 上行网络采样与升降档策略。
    private var uplinkQuality: QualityDirection?

    /// 下行网络采样与升降档策略。
    private var downlinkQuality: QualityDirection?

    /// 当前模型的历史档位存储。
    private var history: QualityHistory?

    /// 向调档流程交付网络质量和采样时刻。
    private var adaptiveListener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?

    /// 保存历史档位的偏好存储。
    private let historyDefaults: UserDefaults

    /// 创建质量控制器并注册 RTC 质量回调。
    ///
    /// - Parameters:
    ///   - rtcManager: 提供网络和媒体质量统计的 RTC 管理器。
    ///   - historyDefaults: 保存按模型隔离的档位历史的偏好存储。
    init(
        rtcManager: any RtcManaging,
        historyDefaults: UserDefaults = .standard
    ) {
        self.historyDefaults = historyDefaults
        rtcManager.setQualityListener(self)
    }

    /// 当前媒体基准及上下行档位快照。
    var qualityConfiguration: QualityConfiguration? {
        listenerLock.withLock { configuration() }
    }

    /// 从媒体基准和模型历史准备本次连接的传输档位。
    ///
    /// - Parameters:
    ///   - baseline: 本地媒体原始输出规格，不随调档改变。
    ///   - model: 用于隔离历史档位的模型标识。
    ///   - isAdaptiveQualityEnabled: 是否启用自适应调档；关闭时从 L1 开始，不读写历史档位。
    /// - Returns: 本次连接的初始上下行配置。
    func prepareQuality(
        baseline: RealtimeVideoFormat,
        model: String,
        isAdaptiveQualityEnabled: Bool
    ) -> QualityConfiguration {
        listenerLock.withLock {
            let history = isAdaptiveQualityEnabled
                ? QualityHistory(model: model, defaults: historyDefaults)
                : nil
            self.history = history
            uplinkQuality = QualityDirection(baseline: baseline, level: history?.read(downlink: false) ?? .l1, downlink: false)
            downlinkQuality = QualityDirection(baseline: baseline, level: history?.read(downlink: true) ?? .l1, downlink: true)
            return configuration()!
        }
    }

    /// 设置内部自适应采样监听，不覆盖接入方的网络监听。
    ///
    /// - Parameter listener: 接收网络质量及单调时钟采样时间；nil 表示移除。
    func setAdaptiveQualityListener(
        _ listener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?
    ) {
        listenerLock.withLock { adaptiveListener = listener }
    }

    /// 根据采样计算候选档位，不提前提交结果。
    ///
    /// - Parameters:
    ///   - quality: 当前上下行网络质量。
    ///   - sampledAt: 单调时钟的采样时间，单位为秒。
    /// - Returns: 满足连续采样和冷却条件的候选档位。
    func proposeQuality(
        _ quality: RealtimeNetworkQuality,
        sampledAt: TimeInterval
    ) -> QualityChange {
        listenerLock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            return QualityChange(
                uplink: uplinkQuality?.observe(quality.uplink, sampledAt: sampledAt, now: now),
                downlink: downlinkQuality?.observe(quality.downlink, sampledAt: sampledAt, now: now)
            )
        }
    }

    /// 提交指定方向的执行结果；仅成功时保存档位历史。
    ///
    /// - Parameters:
    ///   - downlink: true 表示下行，false 表示上行。
    ///   - level: 本次尝试的档位，范围为 1...5。
    ///   - success: 配置是否成功应用。
    func completeQuality(
        downlink: Bool,
        level: RealtimeQualityLevel,
        success: Bool
    ) {
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

    /// 清空连续采样，避免忙碌期间的历史样本触发调档。
    func resetQualitySamples() {
        listenerLock.withLock {
            uplinkQuality?.resetSamples()
            downlinkQuality?.resetSamples()
        }
    }

    /// 释放本次连接的档位及内部采样监听。
    func resetQuality() {
        listenerLock.withLock {
            uplinkQuality = nil
            downlinkQuality = nil
            history = nil
            adaptiveListener = nil
        }
    }

    /// 读取两个方向都已准备完成的质量配置。
    ///
    /// - Returns: 包含基准和上下行档位的配置；未准备完成时返回 `nil`。
    private func configuration() -> QualityConfiguration? {
        guard let uplinkQuality, let downlinkQuality else { return nil }
        return QualityConfiguration(baseline: uplinkQuality.baseline, uplinkLevel: uplinkQuality.level, downlinkLevel: downlinkQuality.level)
    }

    /// 设置视频上行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；未发布或断开连接时收到 nil；传入 nil 清除监听器。
    func setUplinkVideoStatisticsListener(
        _ listener: UplinkVideoStatisticsListener?
    ) {
        listenerLock.withLock {
            uplinkStatisticsVersion &+= 1
            uplinkStatisticsListener = listener
        }
    }

    /// 设置视频下行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；结果流清理时收到 nil；传入 nil 清除监听器。
    func setDownlinkVideoStatisticsListener(
        _ listener: DownlinkVideoStatisticsListener?
    ) {
        listenerLock.withLock {
            downlinkStatisticsVersion &+= 1
            downlinkStatisticsListener = listener
        }
    }

    /// 设置上行统计接收状态，并通知监听器清空旧统计。
    ///
    /// - Parameter enabled: 是否已经发布本地视频。
    func setUplinkVideoStatisticsEnabled(
        _ enabled: Bool
    ) {
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

    /// 设置下行统计目标用户，并通知监听器清空旧统计。
    ///
    /// - Parameter userID: 结果流用户标识；nil 表示停止接收。
    func setDownlinkVideoStatisticsUser(
        _ userID: String?
    ) {
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

    /// 接收本地视频上行统计。
    ///
    /// - Parameter statistics: 当前统计周期的上行指标。
    @MainActor
    func onUplinkVideoStatistics(
        _ statistics: UplinkVideoStatistics
    ) {
        let listener = listenerLock.withLock {
            uplinkStatisticsEnabled ? uplinkStatisticsListener : nil
        }
        listener?(statistics)
    }

    /// 接收远端视频下行统计。
    ///
    /// - Parameter statistics: 当前统计周期的下行指标。
    @MainActor
    func onDownlinkVideoStatistics(
        _ statistics: DownlinkVideoStatistics
    ) {
        let listener = listenerLock.withLock {
            statistics.userID == downlinkStatisticsUser ? downlinkStatisticsListener : nil
        }
        listener?(statistics)
    }

    /// 设置上下行网络质量监听器。
    ///
    /// - Parameter listener: 主线程接收网络质量的回调；`nil` 表示清除。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) {
        listenerLock.withLock {
            networkQualityListener = listener
        }
    }

    /// 设置设备性能告警监听器。
    ///
    /// - Parameter listener: 主线程接收性能受限或恢复的回调；`nil` 表示清除。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) {
        listenerLock.withLock {
            performanceAlarmListener = listener
        }
    }

    /// 接收上下行实时网络质量。
    ///
    /// - Parameters:
    ///   - uplink: 本地发送方向的网络质量。
    ///   - downlink: 远端接收方向的网络质量。
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

    /// 接收性能受限或恢复事件。
    ///
    /// - Parameters:
    ///   - limited: 当前是否受性能限制。
    ///   - suggestedWidth: 建议的视频宽度，单位为像素。
    ///   - suggestedHeight: 建议的视频高度，单位为像素。
    ///   - suggestedFrameRate: 建议的视频帧率，单位为 fps。
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

    /// 将 RTC 质量等级映射为公开网络质量等级。
    ///
    /// - Parameter level: 底层 RTC 网络质量等级。
    /// - Returns: 对应的公开网络质量等级。
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

    /// 从性能告警中提取有效的视频规格建议。
    ///
    /// - Parameters:
    ///   - width: 建议像素宽度。
    ///   - height: 建议像素高度。
    ///   - frameRate: 建议帧率，单位为 fps。
    /// - Returns: 各值均为正数时返回建议规格，否则返回 `nil`。
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
