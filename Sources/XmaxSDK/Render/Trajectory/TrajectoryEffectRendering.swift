import UIKit

/// 一次活动轨迹的稳定标识。
public struct TrajectoryID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// 交给轨迹效果渲染器的可视化触点。
public struct TrajectoryPoint: Sendable {
    public let id: TrajectoryID
    public let location: CGPoint
    public let normalizedLocation: CGPoint
    public let timestamp: TimeInterval

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

    /// 开始一组轨迹。
    func renderBegan(_ points: [TrajectoryPoint])

    /// 更新一组轨迹。
    func renderMoved(_ points: [TrajectoryPoint])

    /// 结束指定轨迹。
    func renderEnded(_ identifiers: [TrajectoryID])

    /// 清除全部轨迹和动画资源。
    func reset()
}
