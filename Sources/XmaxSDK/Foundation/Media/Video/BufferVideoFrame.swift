/// 由内存缓冲区持有像素数据的视频帧。
struct BufferVideoFrame: VideoFrame, Equatable, Sendable {
    let format: VideoFormat
    let timestampUs: Int64
    let rotation: VideoRotation
    let planes: [VideoFramePlane]

    init(
        format: VideoFormat,
        timestampUs: Int64,
        planes: [VideoFramePlane],
        rotation: VideoRotation = .rotation0
    ) throws {
        guard timestampUs >= 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame timestamp must be a non-negative finite number"
            )
        }
        guard !planes.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame must contain at least one plane"
            )
        }

        self.format = format
        self.timestampUs = timestampUs
        self.rotation = rotation
        self.planes = planes
    }
}
