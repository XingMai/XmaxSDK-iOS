import Foundation

/// 持有中性像素数据及时间信息的视频帧。
struct VideoFrame: Equatable, Sendable {
    let bufferReuseID: UUID?
    let format: VideoFormat
    let timestampUs: Int64
    let rotation: VideoRotation
    let planes: [VideoFramePlane]

    init(
        format: VideoFormat,
        timestampUs: Int64,
        planes: [VideoFramePlane],
        rotation: VideoRotation = .rotation0,
        bufferReuseID: UUID? = nil
    ) throws {
        guard timestampUs >= 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame timestamp must be non-negative"
            )
        }
        guard !planes.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame must contain at least one plane"
            )
        }

        self.bufferReuseID = bufferReuseID
        self.format = format
        self.timestampUs = timestampUs
        self.rotation = rotation
        self.planes = planes
    }

    /// 复用像素数据并更新逐帧变化的信息。
    func updating(
        timestampUs: Int64,
        rotation: VideoRotation? = nil
    ) throws -> VideoFrame {
        try VideoFrame(
            format: format,
            timestampUs: timestampUs,
            planes: planes,
            rotation: rotation ?? self.rotation,
            bufferReuseID: bufferReuseID
        )
    }
}
