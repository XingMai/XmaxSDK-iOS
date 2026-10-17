//
//  RtcRoomEventBridge.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@preconcurrency import AgoraRtcKit

/// 将声网单个连接的回调转发给 RTC Manager。
final class RtcRoomEventBridge: NSObject, AgoraRtcEngineDelegate {
    enum Event {
        case joined(UInt)
        case account(UInt, String)
        case publication(UInt, Bool)
        case userJoined(UInt)
        case failure(String)
        case quality(AgoraNetworkQuality, AgoraNetworkQuality)
        case localStats(AgoraRtcLocalVideoStats)
        case remoteStats(AgoraRtcRemoteVideoStats)
    }

    // 事件回调
    private let handler: @Sendable (Event) -> Void

    init(handler: @escaping @Sendable (Event) -> Void) {
        self.handler = handler
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        handler(.joined(uid))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didUserInfoUpdatedWithUserId uid: UInt, userInfo: AgoraUserInfo) {
        guard let account = userInfo.userAccount, !account.isEmpty else { return }
        handler(.account(uid, account))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        handler(.userJoined(uid))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        handler(.publication(uid, false))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didVideoMuted muted: Bool, byUid uid: UInt) {
        handler(.publication(uid, !muted))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didVideoEnabled enabled: Bool, byUid uid: UInt) {
        handler(.publication(uid, enabled))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didLocalVideoEnabled enabled: Bool, byUid uid: UInt) {
        handler(.publication(uid, enabled))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, remoteUserStateChangedOfUid uid: UInt, state: UInt) {
        // AgoraBase.h 中的 USER_STATE 位标记；订阅前也能识别远端发布状态。
        let muteVideo: UInt = 1 << 1
        let enableVideo: UInt = 1 << 4
        let enableLocalVideo: UInt = 1 << 8
        let published = state & muteVideo == 0 && state & enableVideo != 0 && state & enableLocalVideo != 0
        handler(.publication(uid, published))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, remoteVideoStateChangedOfUid uid: UInt, state: AgoraVideoRemoteState, reason: AgoraVideoRemoteReason, elapsed: Int) {
        if state == .starting || state == .decoding {
            handler(.publication(uid, true))
        } else if reason == .remoteMuted || reason == .remoteOffline {
            handler(.publication(uid, false))
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, connectionChangedTo state: AgoraConnectionState, reason: AgoraConnectionChangedReason) {
        if state == .failed {
            handler(.failure("Agora connection failed: \(reason.rawValue)"))
        }
    }

    func rtcEngineRequestToken(_ engine: AgoraRtcEngineKit) {
        handler(.failure("Agora RTC token expired"))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        XmaxLogger.rtc.error(message: "声网 RTC 错误 (Agora RTC Error)\n└─ \(errorCode.rawValue)")
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, networkQuality uid: UInt, txQuality: AgoraNetworkQuality, rxQuality: AgoraNetworkQuality) {
        if uid == 0 { handler(.quality(txQuality, rxQuality)) }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, localVideoStats stats: AgoraRtcLocalVideoStats, sourceType: AgoraVideoSourceType) {
        handler(.localStats(stats))
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, remoteVideoStats stats: AgoraRtcRemoteVideoStats) {
        handler(.remoteStats(stats))
    }
}
