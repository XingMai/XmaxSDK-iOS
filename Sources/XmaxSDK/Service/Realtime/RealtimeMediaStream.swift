/// 实时生成输出的媒体流。
struct RealtimeMediaStream: Sendable {
    let id: String
    let videoTrack: RealtimeVideoTrack?
}
