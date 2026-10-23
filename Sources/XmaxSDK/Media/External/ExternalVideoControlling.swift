//
//  ExternalVideoControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 管理外部视频的供帧绑定、轨道和本地预览。
protocol ExternalVideoControlling: Sendable {

    /// 当前外部视频轨道，解绑后为空。
    var currentTrack: RealtimeVideoTrack? { get }

    /// 校验源规格并绑定供帧，保留接入方的采集资源所有权。
    ///
    /// - Parameter source: 接入方拥有的外部视频源。
    /// - Returns: 可用于预览和生成的本地媒体流。
    /// - Throws: 规格无效、重复绑定、RTC 配置失败或源启动失败时抛出错误。
    @MainActor
    func createExternalVideoStream(
        source: any RealtimeExternalVideoSource
    ) async throws -> RealtimeMediaStream

    /// 停止接收帧，清除预览并通知外部源解绑。
    @MainActor
    func stopExternalVideoStream() async
}
