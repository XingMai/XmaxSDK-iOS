import CoreGraphics

/// 定义模型输入尺寸和平台媒体能力相关的业务规则。
public protocol MediaServicing: Sendable {

    /// 计算满足模型输入约束的尺寸。
    func resolveModelInputSize(_ size: CGSize) throws -> CGSize

    /// 判断当前设备是否支持对指定分辨率的视频进行插帧。
    ///
    /// - Parameter size: 实际发送和渲染的视频分辨率。
    /// - Returns: 当前系统、设备和视频规格均支持插帧时返回 `true`。
    func supportsFrameInterpolation(for size: CGSize) -> Bool
}
