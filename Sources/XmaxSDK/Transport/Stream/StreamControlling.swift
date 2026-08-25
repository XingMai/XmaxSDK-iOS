/// 定义 RTC 房间中的媒体流发布与远端订阅能力。
protocol StreamControlling: Sendable {

    /// 配置当前房间及目标远端用户。
    func configureRoom(
        roomID: String,
        botName: String?
    ) throws

    /// 发布本地视频，并按需发布本地音频。
    func publishLocalStream(includeAudio: Bool) throws

    /// 更新本地音频发布状态。
    func setLocalAudioEnabled(_ enabled: Bool) throws

    /// 清理当前房间中的本地发布与远端订阅状态。
    func resetRoom()
}
