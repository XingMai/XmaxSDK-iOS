//
//  RtcEventListener.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 接收 RTC 媒体和数据信令事件。
protocol RtcEventListener: AnyObject {

    /// 接收远端用户的视频发布状态变化。
    ///
    /// - Parameters:
    ///   - userID: 远端 RTC 用户标识。
    ///   - published: 当前是否已发布视频。
    @MainActor
    func onRemoteVideoPublished(
        userID: String,
        published: Bool
    )

    /// 接收导致当前 RTC 连接或信令传输无法继续的错误。
    ///
    /// - Parameter error: 连接或信令传输错误。
    @MainActor
    func onRtcFailure(
        _ error: XmaxError
    )
}
