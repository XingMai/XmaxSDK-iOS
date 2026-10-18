//
//  RenderControlling.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 异步接收渲染视图采集的交互帧。
typealias RenderInteractionListener = @Sendable (
    _ frame: InteractionFrame
) async -> Void

/// 定义渲染层向 Core 暴露的统一能力。
@MainActor
protocol RenderControlling: AnyObject, Sendable {

    // 插帧状态
    /// 当前远端视频插帧是否处于开启状态。
    var isFrameInterpolationEnabled: Bool { get async }

    /// 更新远端解码帧来源并使旧流的缓存和等待失效。
    ///
    /// - Parameter stream: 新的远端流；传入 `nil` 清除当前来源。
    /// - Throws: 旧流监听解除或新流监听绑定失败时抛出错误。
    func setRemoteStream(_ stream: RemoteStream?) throws

    /// 设置远端最终视频帧监听器。
    ///
    /// - Parameter listener: 在独立串行队列接收最终帧的回调；`nil` 表示清除。
    func setRemoteVideoFrameListener(
        _ listener: RealtimeVideoFrameListener?
    )

    /// 为远端轨道注册视频渲染和轨迹交互绑定。
    ///
    /// - Parameters:
    ///   - track: 需要注册的远端视频轨道。
    ///   - resolvedMediaSize: 处理后的本地媒体尺寸，用于轨迹交互映射。
    ///   - interactionListener: 接收视图交互采样的异步回调。
    func registerRemoteTrack(
        _ track: RealtimeVideoTrack,
        resolvedMediaSize: CGSize,
        interactionListener: @escaping RenderInteractionListener
    )

    /// 开启或关闭远端视频插帧。
    ///
    /// - Parameters:
    ///   - enabled: 是否开启插帧。
    ///   - videoFormat: 期望的回传视频格式；尚未创建本地流时为空。
    /// - Throws: 显式开启时，当前设备或视频规格不支持插帧则抛出错误。
    func setFrameInterpolationEnabled(
        _ enabled: Bool,
        videoFormat: RealtimeVideoFormat?
    ) async throws

    /// 等待当前远端流产生第一张已经完成处理、可立即提交显示的视频帧。
    ///
    /// - Throws: 等待被取消、远端流被重置或首帧等待超时时抛出错误。
    func waitUntilRemoteFrameReady() async throws

    /// 注销远端轨道的所有渲染绑定，重置画面并等待在途帧处理结束。
    ///
    /// - Parameter track: 需要注销的远端轨道；没有轨道时仍会清理帧处理资源。
    /// - Throws: 解除 RTC 视频帧监听失败时抛出错误。
    func resetRemoteTrack(_ track: RealtimeVideoTrack?) async throws
}
