import UIKit

/// 定义远端 RTC 视频流与 UIKit 渲染视图的绑定能力。
@MainActor
protocol RemoteVideoControlling: AnyObject, Sendable {
    /// 更新当前需要渲染的远端视频流。
    func setRemoteStream(_ stream: RemoteStream?) throws

    /// 将远端视频绑定到指定渲染视图。
    func attach(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws

    /// 解除当前视图与远端视频的绑定。
    func detach() throws

    /// 清理远端视频流和渲染视图。
    func reset() throws
}
