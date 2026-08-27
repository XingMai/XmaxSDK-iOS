import UIKit

typealias RtcCameraPreviewReadyListener = @MainActor @Sendable () -> Void

/// 定义 RTC 引擎、房间、媒体传输和渲染绑定能力。
protocol RtcManaging: Sendable {

    /// 初始化 RTC 引擎。
    func initialize() async throws

    /// 销毁 RTC 引擎并释放资源。
    func destroy() async

    /// 应用视频编码配置。
    func configureVideoEncoding(
        _ configuration: VideoEncodingConfiguration
    ) throws

    /// 按指定格式启动 RTC 内部摄像头采集。
    func startVideoCapture(
        width: Int,
        height: Int,
        frameRate: Int
    ) throws

    /// 停止 RTC 内部摄像头采集。
    func stopVideoCapture() throws

    /// 切换 RTC 内部采集使用的摄像头。
    func switchCamera(to position: CameraPosition) throws

    /// 将本地视频源切换为外部视频帧。
    func useExternalVideoSource() throws

    /// 启动 RTC 外部音频源。
    func startExternalAudioSource() throws

    /// 停止 RTC 外部音频源。
    func stopExternalAudioSource() throws

    /// 根据相机位置更新本地视频镜像配置。
    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws

    /// 推送一帧外部视频数据及其可选 SEI。
    func pushExternalVideoFrame(
        _ frame: VideoFrame,
        seiData: Data?
    ) throws

    /// 推送一帧 10 ms PCM 外部音频数据。
    func pushExternalAudioFrame(_ frame: AudioFrame) throws

    /// 加入 RTC 房间。
    func joinRoom(
        configuration: RoomJoinConfiguration
    ) async throws

    /// 离开当前 RTC 房间。
    func leaveRoom() async

    /// 发布本地视频流。
    func publishLocalVideo() throws

    /// 停止发布本地视频流。
    func unpublishLocalVideo() throws

    /// 发布本地音频流。
    func publishLocalAudio() throws

    /// 停止发布本地音频流。
    func unpublishLocalAudio() throws

    /// 更新远端视频流订阅状态。
    func subscribeRemoteVideo(
        userID: String,
        subscribe: Bool
    ) throws

    /// 更新远端音频流订阅状态。
    func subscribeRemoteAudio(
        userID: String,
        subscribe: Bool
    ) throws

    /// 设置指定远端用户的音频播放音量。
    func setRemoteAudioVolume(
        _ volume: Int,
        for userID: String
    ) throws

    /// 将本地视频绑定到渲染视图。
    @MainActor
    func bindLocalVideo(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws

    /// 解除本地视频与渲染视图的绑定。
    @MainActor
    func unbindLocalVideo() throws

    /// 将远端视频流绑定到渲染视图。
    @MainActor
    func bindRemoteVideo(
        _ stream: RemoteStream,
        to view: UIView,
        contentMode: VideoContentMode
    ) throws

    /// 解除远端视频流与渲染视图的绑定。
    @MainActor
    func unbindRemoteVideo(_ stream: RemoteStream) throws

    /// 获取 RTC 渲染库名称。
    var renderLibraryName: String { get }

    /// 向当前 RTC 房间发送消息。
    func sendRoomMessage(_ message: String) throws

    /// 设置 RTC 事件监听器，传入空值时清除监听器。
    func setEventListener(_ listener: (any RtcEventListener)?)

    /// 设置 RTC 摄像头预览就绪监听器，传入空值时清除监听器。
    func setCameraPreviewReadyListener(
        _ listener: RtcCameraPreviewReadyListener?
    )

    /// 设置 RTC 质量事件监听器，传入空值时清除监听器。
    func setQualityListener(_ listener: (any RtcQualityListener)?)
}
