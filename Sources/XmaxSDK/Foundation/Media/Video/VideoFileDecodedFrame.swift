import Foundation

/// 系统视频解码器连续输出的单个文件视频帧。
struct VideoFileDecodedFrame: Equatable, Sendable {
    let data: Data
    let width: Int
    let height: Int
    let stride: Int
    let timestampUs: Int64
    let pixelFormat: VideoPixelFormat

    init(
        data: Data,
        width: Int,
        height: Int,
        stride: Int,
        timestampUs: Int64
    ) throws {
        guard width > 0,
              height > 0,
              width.isMultiple(of: 2),
              height.isMultiple(of: 2),
              stride >= width,
              timestampUs >= 0,
              width <= Int.max / height else {
            throw Self.invalidLayoutError
        }

        let lumaLength = width * height
        guard lumaLength <= Int.max - lumaLength / 2,
              data.count == lumaLength + lumaLength / 2 else {
            throw Self.invalidLayoutError
        }

        self.data = data
        self.width = width
        self.height = height
        self.stride = stride
        self.timestampUs = timestampUs
        pixelFormat = .nv12
    }

    private static var invalidLayoutError: XmaxError {
        XmaxError(
            code: .mediaError,
            message: "Decoded NV12 video frame layout is invalid"
        )
    }
}
