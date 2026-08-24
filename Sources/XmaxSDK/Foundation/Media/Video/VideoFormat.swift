/// 表示视频帧的固定尺寸和像素格式。
struct VideoFormat: Equatable, Sendable {

    let width: Int
    let height: Int
    let pixelFormat: VideoPixelFormat

    init(
        width: Int,
        height: Int,
        pixelFormat: VideoPixelFormat
    ) throws {
        guard width > 0, height > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video width and height must be positive integers"
            )
        }

        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
    }
}
