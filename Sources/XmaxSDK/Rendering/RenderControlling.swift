import Foundation

typealias RenderInteractionListener = @Sendable (
    _ frame: InteractionFrame
) async -> Void

/// 定义渲染层向 Core 暴露的统一能力。
@MainActor
protocol RenderControlling: AnyObject, Sendable {

    /// 当前远端视频插帧是否处于开启状态。
    var isFrameInterpolationEnabled: Bool { get async }

    /// 当前设备是否具备远端视频插帧能力。
    var isFrameInterpolationSupported: Bool { get }

    /// 更新当前需要渲染的远端 RTC 视频流。
    func setRemoteStream(_ stream: RemoteStream?) throws

    /// 为远端视频轨道注册画面和轨迹交互绑定。
    func registerRemoteTrack(
        _ track: RealtimeVideoTrack,
        interactionListener: @escaping RenderInteractionListener
    )

    /// 更新远端轨道的轨迹坐标映射格式。
    func updateRemoteVideoFormat(
        _ videoFormat: RealtimeVideoFormat,
        for track: RealtimeVideoTrack
    )

    /// 开启或关闭远端视频插帧。
    ///
    /// - Parameters:
    ///   - enabled: 是否开启插帧。
    ///   - videoFormat: 当前本地视频格式；尚未创建本地流时为空。
    /// - Throws: 显式开启时，当前设备或视频规格不支持插帧则抛出错误。
    func setFrameInterpolationEnabled(
        _ enabled: Bool,
        videoFormat: RealtimeVideoFormat?
    ) async throws

    /// 注销远端轨道的所有渲染绑定并重置远端画面。
    func resetRemoteTrack(_ track: RealtimeVideoTrack?) throws
}
