import Foundation

/// 接收 SDK 自有像素缓冲区的远端视频帧。
typealias RtcRemoteVideoFrameListener = @Sendable (RealtimeVideoFrame) -> Void

/// 隔离第三方 RTC 引擎能力；不负责连接等待、超时和租约管理。
protocol RtcPlatform: AnyObject, Sendable {

    /// 应用上传视频的编码配置。
    ///
    /// - Parameter configuration: 尺寸、帧率、码率和编码偏好。
    /// - Throws: 厂商引擎拒绝配置时抛出错误。
    func configureVideoEncoding(_ configuration: VideoEncodingConfiguration) throws

    /// 启用外部视频输入。
    ///
    /// - Throws: 视频源配置失败时抛出错误。
    func useExternalVideoSource() throws

    /// 更新上传视频镜像。
    ///
    /// - Parameter position: 当前摄像头位置。
    /// - Throws: 编码镜像配置失败时抛出错误。
    func configureLocalVideoMirror(for position: CameraPosition) throws

    /// 切换至麦克风输入并开始采集。
    ///
    /// - Throws: 音频源切换或采集失败时抛出错误。
    func startAudioCapture() throws

    /// 停止麦克风采集。
    ///
    /// - Throws: 厂商引擎停止采集失败时抛出错误。
    func stopAudioCapture() throws

    /// 启用外部 PCM 输入。
    ///
    /// - Throws: 外部音频轨创建失败时抛出错误。
    func startExternalAudioSource() throws

    /// 停止外部 PCM 输入并释放音频轨。
    ///
    /// - Throws: 音频轨释放失败时抛出错误。
    func stopExternalAudioSource() throws

    /// 推送外部视频帧。
    ///
    /// - Parameter frame: SDK 中性视频帧。
    /// - Throws: 帧格式或数据无效时抛出错误。
    func pushExternalVideoFrame(_ frame: VideoFrame) throws

    /// 推送外部音频帧。
    ///
    /// - Parameter frame: 带时间戳的 10 ms PCM 数据。
    /// - Throws: 帧格式或数据无效时抛出错误。
    func pushExternalAudioFrame(_ frame: AudioFrame) throws

    /// 创建独立的房间适配对象，尚不发起连接。
    ///
    /// - Parameter roomID: 服务端分配的 RTC 房间标识。
    /// - Returns: 尚未加入的房间。
    /// - Throws: 已存在未释放房间时抛出错误。
    func createRoom(roomID: String) throws -> any RtcRoom
}
