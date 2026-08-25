/// 实时视频的尺寸和帧率。
struct RealtimeVideoFormat: Equatable, Sendable {
    let width: Int
    let height: Int
    let fps: Int

    /// 校验尺寸、帧率以及 RTC 所要求的偶数分辨率。
    func validate() throws {
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
