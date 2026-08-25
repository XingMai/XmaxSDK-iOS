/// 实时视频的尺寸和帧率。
public struct RealtimeVideoFormat: Equatable, Sendable {

    /// 视频宽度，单位为像素。
    public let width: Int

    /// 视频高度，单位为像素。
    public let height: Int

    /// 视频帧率。
    public let fps: Int

    /// 创建实时视频格式。
    public init(
        width: Int,
        height: Int,
        fps: Int
    ) {
        self.width = width
        self.height = height
        self.fps = fps
    }

    /// 校验尺寸、帧率以及 RTC 所要求的偶数分辨率。
    public func validate() throws {
        guard width > 0,
              height > 0,
              fps > 0,
              width.isMultiple(of: 2),
              height.isMultiple(of: 2) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Realtime video width and height must be positive " +
                    "even numbers, and fps must be greater than zero"
            )
        }
    }
}
