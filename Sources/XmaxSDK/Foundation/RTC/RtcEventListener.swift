/// 接收 RTC 媒体和数据信令事件。
protocol RtcEventListener: AnyObject {

    /// 处理远端用户的视频发布状态变化。
    @MainActor
    func onRemoteVideoPublished(
        userID: String,
        published: Bool
    )

    /// 处理远端视频流携带的 SEI 消息。
    @MainActor
    func onSeiMessageReceived(
        stream: RemoteStream,
        message: String
    )
}
