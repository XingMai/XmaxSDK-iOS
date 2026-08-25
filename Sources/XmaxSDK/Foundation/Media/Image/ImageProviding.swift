import Foundation
@preconcurrency import CoreGraphics

/// 定义 SDK 内部使用的平台图片处理能力。
protocol ImageProviding: Sendable {

    /// 从图片数据创建一次处理会话。
    func makeProcessingSession(
        data: Data
    ) throws -> any ImageProcessingSession

    /// 居中裁剪并缩放图片，使其完整填满目标尺寸。
    func resizeImageToFill(
        _ image: CGImage,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> CGImage
}
