import CoreGraphics
import Foundation
import UIKit

/// 定义图片选择、尺寸处理和编码能力。
protocol MediaServicing: Sendable {

    /// 从指定 UIKit 页面呈现系统图库并选择一张图片。
    @MainActor
    func pickImage(
        from presentingViewController: UIViewController
    ) async throws -> Data

    /// 计算满足模型输入约束的尺寸。
    func resolveModelInputSize(_ size: CGSize) throws -> CGSize

    /// 将图片处理为模型输入尺寸。
    func resizeToModelInput(
        _ data: Data
    ) async throws -> ProcessedImage

    /// 等比缩放图片，使其不超过指定尺寸。
    func resizeToFit(
        _ data: Data,
        maximumSize: CGSize
    ) async throws -> ProcessedImage

    /// 按指定质量将图片压缩为 JPEG。
    func compressJPEG(
        _ data: Data,
        quality: Double
    ) async throws -> ProcessedImage
}
