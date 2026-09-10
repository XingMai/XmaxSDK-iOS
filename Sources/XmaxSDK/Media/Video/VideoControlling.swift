import Foundation

/// 定义本地文件视频流、音频预览和播放资源管理能力。
protocol VideoControlling: Sendable {

    /// 当前本地文件视频轨道；尚未创建或已停止时为空。
    var currentTrack: RealtimeVideoTrack? { get }

    /// 当前文件视频是否包含由 SDK 管理的音频轨道。
    var hasAudio: Bool { get }

    /// 当前本地文件视频的音频预览音量。
    var localAudioVolume: Float { get async }

    /// 从本地视频文件创建循环播放的媒体流。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地视频文件地址。
    ///   - videoFormat: 期望的输出格式；为空时由视频来源确定，尺寸按模型规则调整。
    /// - Returns: 包含本地文件视频轨道的媒体流。
    /// - Throws: 已有活动视频流、文件或格式无效、权限不足或播放启动失败时抛出错误。
    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 静音或恢复本地文件视频的音频预览，不影响上传的音频帧。
    ///
    /// - Parameter muted: 为 true 时静音，为 false 时恢复配置的预览音量。
    func setLocalAudioPreviewMuted(_ muted: Bool) async

    /// 设置本地文件视频的音频预览音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 0...1 的音量。
    func setLocalAudioVolume(_ volume: Float) async

    /// 停止文件音视频输出，并释放当前轨道、RTC 外部音频和预览资源。
    func stopLocalVideoStream() async
}
