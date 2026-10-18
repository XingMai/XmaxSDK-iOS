//
//  TrajectoryEffectRendering.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// 一次活动轨迹的稳定标识。
public struct TrajectoryID: Hashable, Sendable {

    /// 轨迹标识
    let rawValue: UUID

    /// 创建稳定的轨迹标识。
    ///
    /// - Parameter rawValue: 轨迹使用的唯一值；默认生成新值。
    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// 交给轨迹效果渲染器的可视化触点。
public struct TrajectoryPoint: Sendable {

    /// 轨迹标识
    public let id: TrajectoryID

    /// 触点位置
    public let location: CGPoint
    public let normalizedLocation: CGPoint

    /// 采样时间
    public let timestamp: TimeInterval

    /// 创建交付给效果渲染器的触点。
    ///
    /// - Parameters:
    ///   - id: 该触点所属的轨迹标识。
    ///   - location: 触点在覆盖层中的坐标，单位为点。
    ///   - normalizedLocation: 相对于处理后完整媒体区域的归一化坐标。
    ///   - timestamp: 触点采样的单调时钟时间，单位为秒。
    init(
        id: TrajectoryID,
        location: CGPoint,
        normalizedLocation: CGPoint,
        timestamp: TimeInterval
    ) {
        self.id = id
        self.location = location
        self.normalizedLocation = normalizedLocation
        self.timestamp = timestamp
    }
}

/// 自定义轨迹效果的绘制接口。
///
/// 渲染器只负责视觉表现。触摸采集、坐标映射、采样和网络发送始终由 SDK
/// 管理，替换渲染器不会影响 `tracks` 信令。
@MainActor
public protocol TrajectoryEffectRendering: AnyObject {

    /// 安装在 ``XmaxVideoView`` 上方的轨迹视图。
    var view: UIView { get }

    /// 开始绘制指定触点对应的轨迹。
    ///
    /// - Parameter points: 新开始的轨迹触点。
    func renderBegan(_ points: [TrajectoryPoint])

    /// 更新活动轨迹的触点位置。
    ///
    /// - Parameter points: 当前活动轨迹的最新触点。
    func renderMoved(_ points: [TrajectoryPoint])

    /// 结束指定轨迹的活动绘制。
    ///
    /// - Parameter identifiers: 需要结束的轨迹标识。
    func renderEnded(_ identifiers: [TrajectoryID])

    /// 清除全部轨迹和动画资源。
    func reset()
}
