/// 本地视频文件准备完成后的输出配置。
struct MediaSourceConfiguration: Equatable, Sendable {
    let videoFormat: RealtimeVideoFormat
    let hasAudio: Bool
}
