import Foundation

/// 表示由视频源持有的中性视频帧。
protocol VideoFrame: Sendable {

    /// 像素缓冲区可跨帧复用时提供的稳定标识。
    var bufferReuseID: UUID? { get }

    /// 视频帧格式。
    var format: VideoFormat { get }

    /// 视频帧时间戳，单位为微秒。
    var timestampUs: Int64 { get }

    /// 视频帧需要顺时针旋转的角度。
    var rotation: VideoRotation { get }

    /// 按像素格式约定排列的数据平面。
    var planes: [VideoFramePlane] { get }
}

extension VideoFrame {
    var bufferReuseID: UUID? { nil }
}
