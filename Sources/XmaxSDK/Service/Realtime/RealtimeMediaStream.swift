/// 实时生成输出的媒体流。
public struct RealtimeMediaStream: Sendable {

    /// 媒体流标识。
    public let id: String

    /// 媒体流包含的视频轨道。
    public let videoTrack: RealtimeVideoTrack?
}
