import CoreGraphics
import Foundation

/// 图片缩放或编码后的结果。
struct ProcessedImage: Equatable, Sendable {
    let data: Data
    let size: CGSize
    let contentType: String
}
