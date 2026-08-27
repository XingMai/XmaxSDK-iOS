import Foundation

typealias RenderInteractionListener = @Sendable (
    _ frame: InteractionFrame
) async -> Void

/// 定义渲染层向 Core 暴露的统一能力。
@MainActor
protocol RenderControlling: AnyObject, Sendable {

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

    /// 注销远端轨道的所有渲染绑定并重置远端画面。
    func resetRemoteTrack(_ track: RealtimeVideoTrack?) throws
}
