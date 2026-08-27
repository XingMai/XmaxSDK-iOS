import Foundation
import UIKit

/// 定义本地视频文件准备、循环播放和重新起播能力。
protocol MediaSourceControlling: Sendable {

    /// 当前媒体是否包含音频轨道。
    var hasAudio: Bool { get }

    /// 准备本地视频文件和输出格式。
    func prepare(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> MediaSourceConfiguration

    /// 从文件起点开始循环输出音视频帧。
    func start() async throws

    /// 静音或恢复本地音频预览，不影响播放器和 RTC 音频帧输出。
    ///
    /// - Parameter muted: `true` 表示仅静音本地播放器；
    ///   `false` 表示恢复本地播放器音量。
    func setLocalAudioPreviewMuted(_ muted: Bool) async

    /// 设置本地音频预览音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 `0...1` 的音量。
    func setLocalAudioVolume(_ volume: Float) async

    /// 将本地播放器画面绑定到 SDK 视频视图。
    @MainActor
    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws

    /// 从 SDK 视频视图解除本地播放器画面。
    @MainActor
    func detachPreview(from view: UIView)

    /// 停止输出并释放解码与本地音频播放资源。
    func stop() async
}
