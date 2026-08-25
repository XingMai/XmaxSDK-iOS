import CoreGraphics
import Foundation

/// 图片缩放或编码后的结果。
public struct ProcessedImage: Equatable, Sendable {

    /// 处理并编码后的图片数据。
    public let data: Data

    /// 图片处理后的实际像素尺寸。
    public let size: CGSize

    /// 图片数据对应的 MIME 类型。
    public let contentType: String
}
