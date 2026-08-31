import CoreMedia
import CoreVideo

/// 实时视频链路经过 SDK 处理后使用的视频帧。
public struct RealtimeVideoFrame: @unchecked Sendable {

    // 像素数据
    /// 当前帧的像素缓冲区。
    ///
    /// 像素格式由实际远端视频链路决定。调用方可以持有该缓冲区，并在异步
    /// 编码完成后释放。
    public let pixelBuffer: CVPixelBuffer

    // 时间信息
    /// 当前帧在实时视频时间轴中的显示时间。
    ///
    /// 时间戳不保证从零开始；录制时应以收到的第一帧作为输出时间轴起点。
    public let presentationTimeStamp: CMTime

    /// 当前帧的建议显示时长。
    public let duration: CMTime

    init(
        pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        duration: CMTime = .invalid
    ) {
        self.pixelBuffer = pixelBuffer
        self.presentationTimeStamp = presentationTimeStamp
        self.duration = duration
    }
}

/// 接收远端最终视频帧的监听器。
public typealias RealtimeVideoFrameListener = @Sendable (
    _ frame: RealtimeVideoFrame
) -> Void
