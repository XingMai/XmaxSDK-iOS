import Foundation

/// 定义媒体层向 Core 暴露的统一能力。
protocol MediaControlling: Actor, InteractionControlling {

    /// 当前活动的本地视频轨道。
    var currentTrack: RealtimeVideoTrack? { get }

    /// 当前本地视频格式。
    var currentVideoFormat: RealtimeVideoFormat? { get }

    /// 当前媒体来源是否包含由 SDK 管理的本地音频。
    var hasAudio: Bool { get }

    /// 设置摄像头预览就绪监听器，传入空值时清除监听器。
    func setCameraPreviewReadyListener(
        _ listener: RealtimeCameraPreviewReadyListener?
    )

    /// 创建并持有本地相机媒体流，同时启动采集和本地预览。
    ///
    /// - Parameters:
    ///   - videoFormat: 相机采集使用的目标视频格式。
    ///   - position: 首次启用的摄像头位置。
    /// - Returns: 包含本地相机视频轨道的媒体流。
    /// - Throws: 相机权限、RTC 初始化或采集启动失败时抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream

    /// 使用新的采集参数更新当前相机媒体流。
    ///
    /// - Parameters:
    ///   - videoFormat: 更新后相机采集使用的目标视频格式。
    ///   - position: 更新后启用的摄像头位置。
    /// - Returns: 包含更新后本地相机视频轨道的媒体流。
    /// - Throws: 当前活动来源不是相机、存在并发媒体操作，或相机采集
    ///   配置失败时抛出错误。
    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream

    /// 停止并释放当前本地相机媒体流、预览绑定和 RTC 资源；
    /// 当前来源不是相机时忽略。
    func stopLocalCameraStream() async

    /// 在前置和后置摄像头之间切换当前相机。
    ///
    /// - Returns: 包含更新后摄像头位置的本地媒体流。
    /// - Throws: 当前来源不是相机、存在并发媒体操作或 RTC
    ///   切换失败时抛出错误。
    func switchCamera() async throws -> RealtimeMediaStream

    /// 从编码后的图片数据创建并持有本地图片媒体流。
    ///
    /// - Parameters:
    ///   - imageData: PNG、JPEG 等受支持格式的编码图片数据。
    ///   - videoFormat: 目标本地视频格式；传入空值时根据图片尺寸和
    ///     默认帧率确定。
    /// - Returns: 包含持续输出图片帧的本地视频轨道的媒体流。
    /// - Throws: 图片数据无效、媒体准备或外部视频源启动失败时抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 从已解码图片创建并持有本地图片媒体流。
    ///
    /// - Parameters:
    ///   - decodedImage: 已经完成方向规范化和像素解码的图片。
    ///   - videoFormat: 目标本地视频格式；传入空值时根据图片尺寸和
    ///     默认帧率确定。
    /// - Returns: 包含持续输出图片帧的本地视频轨道的媒体流。
    /// - Throws: 图片像素处理、媒体准备或外部视频源启动失败时抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 从本地图片文件创建并持有本地图片媒体流。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件地址。
    ///   - videoFormat: 目标本地视频格式；传入空值时根据图片尺寸和
    ///     默认帧率确定。
    /// - Returns: 包含持续输出图片帧的本地视频轨道的媒体流。
    /// - Throws: 文件读取、图片解码、媒体准备或外部视频源启动失败时
    ///   抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 停止并释放当前本地图片媒体流、帧输出、预览绑定和 RTC 资源；
    /// 当前来源不是图片时忽略。
    func stopLocalImageStream() async

    /// 从本地视频文件创建并持有本地视频媒体流。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地视频文件地址。
    ///   - videoFormat: 目标本地视频格式；传入空值时根据视频尺寸和
    ///     默认帧率确定。
    /// - Returns: 包含循环输出文件视频帧的本地媒体流。
    /// - Throws: 文件读取、音视频准备、权限或外部媒体源启动失败时
    ///   抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 停止并释放当前本地视频媒体流、音视频输出、预览绑定和 RTC 资源；
    /// 当前来源不是文件视频时忽略。
    func stopLocalVideoStream() async

    /// 静音或恢复文件视频的本地音频预览，不影响播放时间轴和 RTC 音频推流。
    ///
    /// - Parameter muted: `true` 表示仅静音本地播放器；
    ///   `false` 表示恢复本地播放器音量。
    func setLocalAudioPreviewMuted(_ muted: Bool) async

    /// 判断指定媒体流是否由当前活动媒体来源持有。
    ///
    /// - Parameter stream: 需要验证所有权的媒体流。
    /// - Returns: 媒体流的视频轨道由当前活动来源持有时返回 `true`，
    ///   否则返回 `false`。
    func owns(_ stream: RealtimeMediaStream) -> Bool
}
