import Foundation

/// 定义 SDK 内部使用的平台图片解码能力。
protocol ImageProviding: Sendable {

    /// 解码图片数据并应用图片方向。
    func decode(_ data: Data) throws -> any DecodedImage
}
