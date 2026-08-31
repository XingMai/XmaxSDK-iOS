import CoreMedia

/// 定义单帧插值处理器的内部能力。
protocol FrameInterpolationManaging: AnyObject, Sendable {

    /// 判断处理器是否仍匹配输入帧的视频规格。
    ///
    /// - Parameter frame: 待比较的视频帧。
    /// - Returns: 分辨率与像素格式均匹配时返回 `true`。
    func matches(_ frame: RealtimeVideoFrame) -> Bool

    /// 在前一帧和当前帧之间生成一个中间帧。
    ///
    /// - Parameters:
    ///   - frame: 当前解码视频帧。
    ///   - sourceDuration: 当前源帧使用的显示时长。
    /// - Returns: 首帧返回原帧，后续返回中间帧与当前原帧。
    /// - Throws: 像素缓冲区准备或 VideoToolbox 处理失败时抛出错误。
    func process(
        _ frame: RealtimeVideoFrame,
        sourceDuration: CMTime
    ) async throws -> [RealtimeVideoFrame]

    /// 清除前一帧和时间戳状态。
    func reset()
}
