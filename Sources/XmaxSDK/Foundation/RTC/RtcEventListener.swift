//
//  RtcEventListener.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A listener for RTC media and signaling events.
protocol RtcEventListener: AnyObject {

    /// Reports remote video publication changes.
    ///
    /// - Parameters:
    ///   - userID: The remote RTC user identifier.
    ///   - published: Whether video is currently published.
    @MainActor
    func onRemoteVideoPublished(
        userID: String,
        published: Bool
    )

    /// Reports a failure preventing further connection or signaling.
    ///
    /// - Parameter error: The connection or signaling failure.
    @MainActor
    func onRtcFailure(
        _ error: XmaxError
    )
}
