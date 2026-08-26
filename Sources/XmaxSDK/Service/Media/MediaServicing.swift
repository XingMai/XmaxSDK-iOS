import CoreGraphics

/// 定义与模型输入约束相关的媒体业务规则。
public protocol MediaServicing: Sendable {

    /// 计算满足模型输入约束的尺寸。
    func resolveModelInputSize(_ size: CGSize) throws -> CGSize
}
