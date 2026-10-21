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

/// 定义网络质量与设备性能告警的监听能力。
protocol QualityControlling: Sendable {

    /// 当前连接的传输档位；尚未准备时为空。
    var qualityConfiguration: QualityConfiguration? { get }

    /// 从媒体基准和模型历史准备本次连接的传输档位。
    ///
    /// - Parameters:
    ///   - baseline: 本地媒体原始输出规格，不随调档改变。
    ///   - model: 用于隔离历史档位的模型标识。
    /// - Returns: 本次连接的初始上下行配置。
    func prepareQuality(
        baseline: RealtimeVideoFormat,
        model: String
    ) -> QualityConfiguration

    /// 设置内部自适应采样监听，不覆盖接入方的网络监听。
    ///
    /// - Parameter listener: 接收网络质量及单调时钟采样时间；nil 表示移除。
    func setAdaptiveQualityListener(
        _ listener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?
    )

    /// 根据采样计算候选档位，不提前提交结果。
    ///
    /// - Parameters:
    ///   - quality: 当前上下行网络质量。
    ///   - sampledAt: 单调时钟的采样时间，单位为秒。
    /// - Returns: 满足连续采样和冷却条件的候选档位。
    func proposeQuality(
        _ quality: RealtimeNetworkQuality,
        sampledAt: TimeInterval
    ) -> QualityChange

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
    )

    /// 清空连续采样，避免忙碌期间的历史样本触发调档。
    func resetQualitySamples()

    /// 释放本次连接的档位及内部采样监听。
    func resetQuality()

    /// 设置上行统计接收状态，并通知监听器清空旧统计。
    ///
    /// - Parameter enabled: 是否已经发布本地视频。
    func setUplinkVideoStatisticsEnabled(
        _ enabled: Bool
    )

    /// 设置下行统计目标用户，并通知监听器清空旧统计。
    ///
    /// - Parameter userID: 结果流用户标识；nil 表示停止接收。
    func setDownlinkVideoStatisticsUser(
        _ userID: String?
    )

    /// 设置视频上行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；未发布或断开连接时收到 nil；传入 nil 清除监听器。
    func setUplinkVideoStatisticsListener(
        _ listener: UplinkVideoStatisticsListener?
    )

    /// 设置视频下行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；结果流清理时收到 nil；传入 nil 清除监听器。
    func setDownlinkVideoStatisticsListener(
        _ listener: DownlinkVideoStatisticsListener?
    )

    /// 设置上下行网络质量监听器。
    ///
    /// - Parameter listener: 主线程接收网络质量的回调；`nil` 表示清除。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    )

    /// 设置设备性能告警监听器。
    ///
    /// - Parameter listener: 主线程接收性能受限或恢复的回调；`nil` 表示清除。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    )
}
