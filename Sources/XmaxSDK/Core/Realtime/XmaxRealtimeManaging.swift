import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 定义 SDK 对接入方提供的实时媒体与生成控制能力。
public protocol XmaxRealtimeManaging: Sendable {

    /// 实时能力配置。
    var options: RealtimeConfiguration { get }


    /// 当前实时连接与生成状态。
    var currentState: RealtimeState { get async }


    /// 当前实际生效的远端视频插帧状态。
    var isFrameInterpolationEnabled: Bool { get async }


    /// 设置实时状态监听器。
    ///
    /// - Parameter listener: 实时状态回调；传入 `nil` 时清除监听器。
    func setStateListener(
        _ listener: RealtimeStateListener?
    ) async


    /// 设置实时错误监听器。
    ///
    /// - Parameter listener: 实时错误回调；传入 `nil` 时清除监听器。
    func setErrorListener(
        _ listener: RealtimeErrorListener?
    ) async


    /// 设置摄像头预览就绪监听器。
    ///
    /// - Parameter listener: 预览首帧就绪回调；传入 `nil` 时清除监听器。
    func setCameraPreviewReadyListener(
        _ listener: RealtimeCameraPreviewReadyListener?
    ) async


    /// 设置网络质量监听器。
    ///
    /// - Parameter listener: 上下行网络质量回调；传入 `nil` 时清除监听器。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) async


    /// 设置设备性能告警监听器。
    ///
    /// - Parameter listener: 设备性能告警回调；传入 `nil` 时清除监听器。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) async


    /// 设置本地媒体预览音量。
    ///
    /// - Parameter volume: 本地预览音量，取值范围为 `0...1`。
    /// - Throws: 音量超出有效范围时抛出错误。
    func setLocalAudioVolume(
        _ volume: Float
    ) async throws


    /// 设置远端生成音频播放音量。
    ///
    /// 尚未连接或订阅远端流时保存配置，并在远端音频开始播放前应用。
    ///
    /// - Parameter volume: 远端播放音量，取值范围为 `0...1`。
    /// - Throws: 音量超出有效范围或 RTC 音量配置失败时抛出错误。
    func setRemoteAudioVolume(
        _ volume: Float
    ) async throws


    /// 开启或关闭远端生成画面的插帧。
    ///
    /// 设置结果覆盖初始化配置，并持续应用于当前及后续远端视频流。显式开启
    /// 时，如果当前设备或已有本地流不支持插帧，则保持原状态并抛出错误。
    ///
    /// - Parameter enabled: 是否开启远端视频插帧。
    /// - Throws: 当前设备、视频规格或帧处理器不支持插帧时抛出错误。
    func setFrameInterpolationEnabled(
        _ enabled: Bool
    ) async throws


    /// 创建本地相机流并开始预览。
    ///
    /// - Parameters:
    ///   - videoFormat: 相机采集的视频规格。
    ///   - position: 首次启用的摄像头位置。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream


    /// 停止本地相机流并释放本地预览与 RTC 资源。
    func stopLocalCameraStream() async throws


    /// 切换前后置摄像头。
    ///
    /// 生成过程中调用时，SDK 会停止当前生成、切换摄像头，并使用缓存的生成
    /// 条件恢复生成；RTC 连接保持不变。连接或生成正在启动时不可切换。
    ///
    /// - Returns: 复用原视频轨道并更新摄像头位置后的本地媒体流。
    /// - Throws: 当前没有摄像头流、实时流程正在启动，或摄像头切换及生成恢复
    ///   失败时抛出错误。
    func switchCamera() async throws -> RealtimeMediaStream


    /// 从编码后的图片数据创建持续输出帧的媒体流。
    ///
    /// - Parameters:
    ///   - imageData: JPEG、PNG 等受支持格式的编码图片数据。
    ///   - videoFormat: 输出视频规格；传入 `nil` 时根据图片原始尺寸生成。
    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream


#if canImport(UIKit)
    /// 从 UIKit 图片创建持续输出帧的媒体流。
    ///
    /// - Parameters:
    ///   - image: 用作本地输入的 UIKit 图片。
    ///   - videoFormat: 输出视频规格；传入 `nil` 时根据图片原始尺寸生成。
    func createLocalImageStream(
        image: UIImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream
#endif


    /// 从本地图片文件创建持续输出帧的媒体流。
    ///
    /// - Parameters:
    ///   - fileURL: 本地图片文件 URL。
    ///   - videoFormat: 输出视频规格；传入 `nil` 时根据图片原始尺寸生成。
    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream


    /// 停止本地图片流并释放本地预览与 RTC 资源。
    func stopLocalImageStream() async throws


    /// 从本地视频文件创建循环播放的音视频流。
    ///
    /// - Parameters:
    ///   - fileURL: 本地视频文件 URL。
    ///   - videoFormat: 输出视频规格；传入 `nil` 时使用视频原始尺寸。
    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream


    /// 停止本地文件视频流并释放音视频、预览与 RTC 资源。
    func stopLocalVideoStream() async throws


    /// 使用当前 Manager 创建的本地流建立实时连接。
    ///
    /// - Parameter localStream: 当前 Manager 创建并持有的本地媒体流。
    func connect(
        localStream: RealtimeMediaStream
    ) async throws -> RealtimeMediaStream


    /// 断开实时连接并保留当前本地媒体预览。
    func disconnect() async


    /// 关闭当前实时生命周期并释放连接、本地媒体和 RTC Engine。
    ///
    /// 关闭期间重复调用会等待同一个释放任务；关闭完成后仍可重新创建本地流。
    func close() async


    /// 开始生成，生成中再次调用时更新当前条件。
    ///
    /// - Parameter context: 本次生成条件；首次生成不能为空，后续传入 `nil`
    ///   时复用缓存条件。
    func startGeneration(
        context: RealtimeContext?
    ) async throws


    /// 使用当前本地流按需建立连接并开始生成。
    ///
    /// 文件视频在连接和生成期间保持本地播放器持续运行；已经连接时直接复用
    /// 当前连接。返回的远端流可交给统一视频视图显示生成结果。
    ///
    /// - Parameters:
    ///   - localStream: 当前 Manager 创建并持有的本地媒体流。
    ///   - context: 本次生成条件；首次生成不能为空。
    /// - Returns: 当前 RTC 连接对应的远端媒体流。
    /// - Throws: 本地流无效、连接失败或生成启动失败时抛出错误。
    func startGeneration(
        localStream: RealtimeMediaStream,
        context: RealtimeContext?
    ) async throws -> RealtimeMediaStream


    /// 停止当前生成任务并保留实时连接。
    func stopGeneration() async
}

public extension XmaxRealtimeManaging {
    /// 使用前置摄像头创建本地相机流并开始预览。
    ///
    /// - Parameter videoFormat: 相机采集的视频规格。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
    }


    /// 根据编码后的图片数据创建本地图片流并开始预览。
    ///
    /// - Parameter imageData: JPEG、PNG 等受支持格式的编码图片数据。
    func createLocalImageStream(
        imageData: Data
    ) async throws -> RealtimeMediaStream {
        try await createLocalImageStream(
            imageData: imageData,
            videoFormat: nil
        )
    }


    /// 根据图片原始尺寸创建本地图片流并开始预览。
    ///
    /// - Parameter fileURL: 本地图片文件 URL。
    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createLocalImageStream(
            fileURL: fileURL,
            videoFormat: nil
        )
    }


    /// 根据视频原始尺寸创建本地文件视频流并开始预览。
    ///
    /// - Parameter fileURL: 本地视频文件 URL。
    func createLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createLocalVideoStream(
            fileURL: fileURL,
            videoFormat: nil
        )
    }


    /// 使用缓存条件开始生成；首次生成仍需显式传入条件。
    func startGeneration() async throws {
        try await startGeneration(context: nil)
    }


    /// 使用当前本地流和缓存条件按需连接并开始生成。
    ///
    /// - Parameter localStream: 当前 Manager 创建并持有的本地媒体流。
    func startGeneration(
        localStream: RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        try await startGeneration(
            localStream: localStream,
            context: nil
        )
    }
}
