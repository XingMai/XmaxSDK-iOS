//
//  RtcRoom.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 与厂商无关的单次房间连接事件。
enum RtcRoomEvent: Sendable {
    case joined
    case publication(userID: String, published: Bool)
    case failure(XmaxError)
    case quality(uplink: RtcQualityLevel, downlink: RtcQualityLevel)
    case uplinkVideoStatistics(UplinkVideoStatistics)
    case downlinkVideoStatistics(DownlinkVideoStatistics)
    case performance(limited: Bool, width: Int, height: Int, frameRate: Int)
}

/// 隔离第三方 RTC 房间能力。每个实例只服务一次连接。
protocol RtcRoom: AnyObject, Sendable {

    /// 设置房间事件回调。
    ///
    /// - Parameter listener: 中性事件回调；传入 nil 清除监听。
    func setEventListener(_ listener: (@Sendable (RtcRoomEvent) -> Void)?)

    /// 发起进房；成功通过 joined 事件通知。
    ///
    /// - Parameter configuration: 房间、用户账号和令牌。
    /// - Throws: 进房调用立即失败时抛出错误。
    func join(configuration: RoomJoinConfiguration) throws

    /// 停止回调、清理信令和帧监听，并离开房间；重复调用无副作用。
    func destroy()

    /// 更新本地视频发布状态。
    ///
    /// - Parameter publish: 是否发布外部视频轨。
    /// - Throws: 发布配置失败时抛出错误。
    func publishLocalVideo(_ publish: Bool) throws

    /// 更新本地音频发布状态。
    ///
    /// - Parameter publish: 是否发布当前音频源。
    /// - Throws: 发布配置失败时抛出错误。
    func publishLocalAudio(_ publish: Bool) throws

    /// 更新远端视频订阅。
    ///
    /// - Parameters:
    ///   - userID: 服务端分配的 RTC 用户账号。
    ///   - subscribe: 是否订阅视频。
    /// - Throws: 用户映射或订阅失败时抛出错误。
    func subscribeRemoteVideo(userID: String, subscribe: Bool) throws

    /// 更新远端音频订阅。
    ///
    /// - Parameters:
    ///   - userID: 服务端分配的 RTC 用户账号。
    ///   - subscribe: 是否订阅音频。
    /// - Throws: 用户映射或订阅失败时抛出错误。
    func subscribeRemoteAudio(userID: String, subscribe: Bool) throws

    /// 设置远端音频播放音量。
    ///
    /// - Parameters:
    ///   - volume: 0 到 100 的音量。
    ///   - userID: RTC 用户账号。
    /// - Throws: 用户映射或音量配置失败时抛出错误。
    func setRemoteAudioVolume(_ volume: Int, for userID: String) throws

    /// 设置远端解码帧监听。
    ///
    /// - Parameters:
    ///   - listener: 帧回调；传入 nil 清除监听。
    ///   - userID: RTC 用户账号。
    /// - Throws: 用户映射失败时抛出错误。
    func setRemoteVideoFrameListener(_ listener: RtcRemoteVideoFrameListener?, for userID: String)
        throws

    /// 将信令加入房间发送队列。
    ///
    /// - Parameters:
    ///   - message: 完整 JSON 信令。
    ///   - reportFailure: 异步发送失败时是否通知房间故障；false 仅记录日志并由等待调用抛出。
    /// - Throws: 信令无效或队列不可用时抛出错误。
    /// - Returns: 本条信令的发送任务。
    @discardableResult
    func sendRoomMessage(_ message: String, reportFailure: Bool) throws -> Task<Void, any Error>

    /// 等待此前排队的信令提交给 RTC。
    ///
    /// - Throws: 发送失败、离房或调用取消时抛出错误。
    func awaitPendingMessages() async throws
}

extension RtcRoom {
    func sendRoomMessage(_ message: String) throws {
        try sendRoomMessage(message, reportFailure: true)
    }
}
