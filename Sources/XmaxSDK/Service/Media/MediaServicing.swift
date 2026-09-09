import CoreGraphics

/// 定义模型输入尺寸和平台媒体能力相关的业务规则。
public protocol MediaServicing: Sendable {

    /// 当前媒体规则使用的实时生成模型。
    var model: RealtimeModel { get }

    /// 计算满足模型输入约束的尺寸。
    ///
    /// - Parameter size: 原始媒体的显示尺寸。
    /// - Returns: 按当前模型的像素面积上下限及对齐要求计算的输入尺寸。
    /// - Throws: 尺寸无效时抛出 `XmaxError`。
    func resolveModelInputSize(_ size: CGSize) throws -> CGSize

    /// 计算保持原始比例且满足插帧像素预算的回传尺寸。
    ///
    /// - Parameter size: 生成画面的整数像素尺寸。
    /// - Returns: 不放大、宽高均为偶数且总像素不超过 900000 的等比例尺寸。
    ///   不应用模型输入的最小面积或对齐规则，也不检查设备能力。
    /// - Throws: 尺寸无效，或不存在满足约束的等比例尺寸时抛出 `XmaxError`。
    func resolveFrameInterpolationSize(_ size: CGSize) throws -> CGSize

    /// 判断当前设备是否支持对指定分辨率的视频进行插帧。
    ///
    /// - Parameter size: 客户端收到的、用于插帧处理的视频分辨率。
    /// - Returns: 当前系统、设备和视频规格均支持插帧时返回 `true`。
    func supportsFrameInterpolation(for size: CGSize) -> Bool
}
