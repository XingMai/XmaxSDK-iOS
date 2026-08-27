import CoreMedia
import CoreVideo

/// 持有解码后像素缓冲区及其显示时间信息的视频帧。
struct DecodedVideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTimeStamp: CMTime
    let duration: CMTime

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
