import Foundation
import UIKit

typealias VideoPreviewResume = @Sendable () async -> Void

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

    /// 为新一轮生成从指定文件时间重新建立同步时间线。
    ///
    /// - Parameter mediaTimeUs: 音频和视频共同使用的文件内起播时间。
    func restart(from mediaTimeUs: Int64) async throws

    /// 暂停本地播放器并返回当前文件时间检查点。
    func pause() async -> Int64?

    /// 解除本地静态帧冻结，并在需要时恢复播放器。
    func resumePreviewIfNeeded() async

    /// 启用或暂停本地音频预览，不影响 RTC 音频帧输出。
    ///
    /// - Parameter enabled: `true` 表示播放本地预览音频；
    ///   `false` 表示立即清空缓冲并保持静音。
    func setLocalAudioPreviewEnabled(_ enabled: Bool) async throws

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
