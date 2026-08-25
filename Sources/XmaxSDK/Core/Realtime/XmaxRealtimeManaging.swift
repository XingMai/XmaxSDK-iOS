import Foundation

/// 定义 SDK 对接入方提供的实时媒体与生成控制能力。
public protocol XmaxRealtimeManaging: Sendable {

    /// 实时能力配置。
    var options: RealtimeConfiguration { get }

    /// 当前实时连接与生成状态。
    var currentState: RealtimeState { get async }

    /// 设置实时状态监听器，传入空值时清除监听器。
    func setStateListener(_ listener: RealtimeStateListener?) async

    /// 设置实时错误监听器，传入空值时清除监听器。
    func setErrorListener(_ listener: RealtimeErrorListener?) async

    /// 设置网络质量监听器，传入空值时清除监听器。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) async

    /// 设置设备性能告警监听器，传入空值时清除监听器。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) async

    /// 创建本地相机流并开始预览。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream

    /// 将当前本地媒体流替换为相机流。
    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream

    /// 停止本地相机流并释放本地预览与 RTC 资源。
    func stopLocalCameraStream() async throws

    /// 切换前后置摄像头。
    func switchCamera() async throws -> RealtimeMediaStream

    /// 从本地图片文件创建持续输出帧的媒体流。
    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 将当前本地媒体流替换为图片流。
    func replaceLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 停止本地图片流并释放本地预览与 RTC 资源。
    func stopLocalImageStream() async throws

    /// 从本地视频文件创建循环播放的音视频流。
    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 将当前本地媒体流替换为文件视频流。
    func replaceLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 停止本地文件视频流并释放音视频、预览与 RTC 资源。
    func stopLocalVideoStream() async throws

    /// 使用当前 Manager 创建的本地流建立实时连接。
    func connect(
        localStream: RealtimeMediaStream
    ) async throws -> RealtimeMediaStream

    /// 断开实时连接并保留当前本地媒体预览。
    func disconnect() async

    /// 开始生成，生成中再次调用时更新当前条件。
    func startGeneration(context: RealtimeContext?) async throws

    /// 停止当前生成任务并保留实时连接。
    func stopGeneration() async
}

public extension XmaxRealtimeManaging {
    /// 使用前置摄像头创建本地相机流并开始预览。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
    }

    /// 使用前置摄像头替换当前本地媒体流。
    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat
    ) async throws -> RealtimeMediaStream {
        try await replaceLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
    }

    /// 根据图片原始尺寸创建本地图片流并开始预览。
    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createLocalImageStream(
            fileURL: fileURL,
            videoFormat: nil
        )
    }

    /// 根据图片原始尺寸替换当前本地媒体流。
    func replaceLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await replaceLocalImageStream(
            fileURL: fileURL,
            videoFormat: nil
        )
    }

    /// 根据视频原始尺寸创建本地文件视频流并开始预览。
    func createLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createLocalVideoStream(
            fileURL: fileURL,
            videoFormat: nil
        )
    }

    /// 根据视频原始尺寸替换当前本地媒体流。
    func replaceLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await replaceLocalVideoStream(
            fileURL: fileURL,
            videoFormat: nil
        )
    }

    /// 使用缓存条件开始生成；首次生成仍需显式传入条件。
    func startGeneration() async throws {
        try await startGeneration(context: nil)
    }
}
