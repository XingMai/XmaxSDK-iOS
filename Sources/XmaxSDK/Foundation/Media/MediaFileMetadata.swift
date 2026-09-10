/// 本地媒体文件中视频、音频和时间线所需的元数据。
struct MediaFileMetadata: Equatable, Sendable {
    let width: Int
    let height: Int
    let rotation: VideoRotation
    let durationSeconds: Double
    let hasAudio: Bool
}
