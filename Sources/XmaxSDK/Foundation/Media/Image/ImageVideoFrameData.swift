import Foundation

/// 表示由图片解码得到的中性视频帧像素数据。
struct ImageVideoFrameData: Equatable, Sendable {
    let data: Data
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixelFormat: VideoPixelFormat
}
