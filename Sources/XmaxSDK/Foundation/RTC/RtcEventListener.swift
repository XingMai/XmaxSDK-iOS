//
//  RtcEventListener.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 接收 RTC 媒体和数据信令事件。
protocol RtcEventListener: AnyObject {

    /// 处理远端用户的视频发布状态变化。
    @MainActor
    func onRemoteVideoPublished(
        userID: String,
        published: Bool
    )

    /// 处理当前 RTC 连接或信令传输无法继续的错误。
    @MainActor
    func onRtcFailure(_ error: XmaxError)
}
