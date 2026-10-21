//
//  RtcRoomEventBridge.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@preconcurrency import AgoraRtcKit

/// 将声网单个连接的回调转发给 RTC Manager。
final class RtcRoomEventBridge: NSObject, AgoraRtcEngineDelegate {

    /// 封装单次声网连接的用户、媒体及质量事件。
    enum Event {

        /// 本地用户进房成功，携带声网数字 UID。
        case joined(UInt)

        /// 数字 UID 与用户账号的映射更新。
        case account(UInt, String)

        /// 远端用户的视频发布状态变化。
        case publication(UInt, Bool)

        /// 远端用户加入房间。
        case userJoined(UInt)

        /// 声网房间错误及其说明。
        case failure(String)

        /// 上行和下行网络质量评级更新。
        case quality(AgoraNetworkQuality, AgoraNetworkQuality)

        /// 本地视频统计更新。
        case localStats(AgoraRtcLocalVideoStats)

        /// 远端视频统计更新。
        case remoteStats(AgoraRtcRemoteVideoStats)
    }

    /// 接收转换后事件的回调。
    private let handler: @Sendable (Event) -> Void

    /// 创建房间事件桥接器。
    init(
        handler: @escaping @Sendable (Event) -> Void
    ) {
        self.handler = handler
    }

    /// 转发本地进房成功事件。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - channel: 已加入的频道标识。
    ///   - uid: 本地用户的数字标识。
    ///   - elapsed: 进房调用至成功的耗时，单位为毫秒。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didJoinChannel channel: String,
        withUid uid: UInt,
        elapsed: Int
    ) {
        handler(.joined(uid))
    }

    /// 转发远端数字用户标识与账号的映射。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - uid: 远端用户数字标识。
    ///   - userInfo: 包含用户账号的信息。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didUserInfoUpdatedWithUserId uid: UInt,
        userInfo: AgoraUserInfo
    ) {
        guard let account = userInfo.userAccount, !account.isEmpty else { return }
        handler(.account(uid, account))
    }

    /// 转发远端用户加入事件。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - uid: 加入的远端用户数字标识。
    ///   - elapsed: 加入通知的耗时，单位为毫秒。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didJoinedOfUid uid: UInt,
        elapsed: Int
    ) {
        handler(.userJoined(uid))
    }

    /// 在远端离开时通知其视频已停止发布。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - uid: 离开的远端用户数字标识。
    ///   - reason: 用户离线原因。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didOfflineOfUid uid: UInt,
        reason: AgoraUserOfflineReason
    ) {
        handler(.publication(uid, false))
    }

    /// 将远端视频静音变化转换为发布状态。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - muted: 远端视频是否被静音。
    ///   - uid: 远端用户数字标识。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didVideoMuted muted: Bool,
        byUid uid: UInt
    ) {
        handler(.publication(uid, !muted))
    }

    /// 将远端视频启用变化转换为发布状态。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - enabled: 远端视频是否启用。
    ///   - uid: 远端用户数字标识。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didVideoEnabled enabled: Bool,
        byUid uid: UInt
    ) {
        handler(.publication(uid, enabled))
    }

    /// 将远端视频启用变化转换为发布状态。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - enabled: 远端视频是否启用。
    ///   - uid: 远端用户数字标识。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didLocalVideoEnabled enabled: Bool,
        byUid uid: UInt
    ) {
        handler(.publication(uid, enabled))
    }

    /// 根据远端用户状态位计算视频发布状态。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - uid: 远端用户数字标识。
    ///   - state: 远端用户的状态位集合。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        remoteUserStateChangedOfUid uid: UInt,
        state: UInt
    ) {
        // AgoraBase.h 中的 USER_STATE 位标记；订阅前也能识别远端发布状态。
        let muteVideo: UInt = 1 << 1
        let enableVideo: UInt = 1 << 4
        let enableLocalVideo: UInt = 1 << 8
        let published = state & muteVideo == 0 && state & enableVideo != 0 && state & enableLocalVideo != 0
        handler(.publication(uid, published))
    }

    /// 根据远端视频接收状态转发视频发布或停止事件。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - uid: 远端用户数字标识。
    ///   - state: 当前视频接收状态。
    ///   - reason: 状态变化原因。
    ///   - elapsed: 状态变化耗时，单位为毫秒。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        remoteVideoStateChangedOfUid uid: UInt,
        state: AgoraVideoRemoteState,
        reason: AgoraVideoRemoteReason,
        elapsed: Int
    ) {
        if state == .starting || state == .decoding {
            handler(.publication(uid, true))
        } else if reason == .remoteMuted || reason == .remoteOffline {
            handler(.publication(uid, false))
        }
    }

    /// 在 RTC 连接失败时转发连接错误。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - state: 当前连接状态。
    ///   - reason: 连接状态变化原因。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        connectionChangedTo state: AgoraConnectionState,
        reason: AgoraConnectionChangedReason
    ) {
        if state == .failed {
            handler(.failure("Agora connection failed: \(reason.rawValue)"))
        }
    }

    /// 在令牌过期时通知房间连接失败。
    ///
    /// - Parameter engine: 请求新令牌的 RTC 引擎。
    func rtcEngineRequestToken(
        _ engine: AgoraRtcEngineKit
    ) {
        handler(.failure("Agora RTC token expired"))
    }

    /// 记录声网引擎上报的错误。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - errorCode: 声网错误码。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didOccurError errorCode: AgoraErrorCode
    ) {
        XmaxLogger.rtc.error(message: "声网 RTC 错误 (Agora RTC Error)\n└─ \(errorCode.rawValue)")
    }

    /// 转发本地用户的上下行网络质量。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - uid: 质量统计对应的用户；零表示本地用户。
    ///   - txQuality: 上行网络质量。
    ///   - rxQuality: 下行网络质量。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        networkQuality uid: UInt,
        txQuality: AgoraNetworkQuality,
        rxQuality: AgoraNetworkQuality
    ) {
        if uid == 0 { handler(.quality(txQuality, rxQuality)) }
    }

    /// 转发本地视频上行统计。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - stats: 当前本地视频统计。
    ///   - sourceType: 统计对应的视频源类型。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        localVideoStats stats: AgoraRtcLocalVideoStats,
        sourceType: AgoraVideoSourceType
    ) {
        handler(.localStats(stats))
    }

    /// 转发远端视频下行统计。
    ///
    /// - Parameters:
    ///   - engine: 产生回调的 RTC 引擎。
    ///   - stats: 当前远端视频统计。
    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        remoteVideoStats stats: AgoraRtcRemoteVideoStats
    ) {
        handler(.remoteStats(stats))
    }
}
