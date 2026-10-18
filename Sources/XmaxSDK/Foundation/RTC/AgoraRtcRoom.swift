//
//  AgoraRtcRoom.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AgoraRtcKit
import Foundation

/// 封装单次声网连接、用户映射、发布订阅和 DataStream 信令。
final class AgoraRtcRoom: RtcRoom, @unchecked Sendable {

    /// 平台资源
    private let platform: AgoraRtcPlatform
    private let roomID: String
    let connection = AgoraRtcConnection()
    private var bridge: RtcRoomEventBridge?
    private var videoSink: RtcRemoteVideoSink?

    /// 用户与事件
    private var listener: (@Sendable (RtcRoomEvent) -> Void)?
    private var accounts: [UInt: String] = [:]
    private var publications: [UInt: Bool] = [:]
    private var frameListeners: [UInt: RtcRemoteVideoFrameListener] = [:]

    /// 信令资源
    private var dataStreamID = 0
    private var sender: RtcMessageQueue?

    /// 连接状态（由 platform.lock 保护）
    private var account: String?
    private(set) var isJoined = false
    private(set) var isClosed = false

    /// 创建服务于单次连接的声网房间。
    ///
    /// - Parameters:
    ///   - platform: 持有声网引擎的平台适配器。
    ///   - roomID: RTC 房间标识。
    init(platform: AgoraRtcPlatform, roomID: String) {
        self.platform = platform
        self.roomID = roomID
        connection.channelId = roomID
    }

    /// 设置房间事件回调。
    ///
    /// - Parameter listener: 中性事件回调；传入 nil 清除监听。
    func setEventListener(_ listener: (@Sendable (RtcRoomEvent) -> Void)?) {
        platform.lock.withLock {
            self.listener = isClosed ? nil : listener
        }
    }

    /// 发起进房；成功通过 joined 事件通知。
    ///
    /// - Parameter configuration: 房间、用户账号和令牌。
    /// - Throws: 进房调用立即失败时抛出错误。
    func join(configuration: RoomJoinConfiguration) throws {
        try platform.lock.withLock {
            guard !isClosed, account == nil, configuration.roomID == roomID else {
                throw XmaxError(code: .rtcError, message: "RTC room cannot be joined")
            }
            account = configuration.userID
            let bridge = RtcRoomEventBridge { [weak self] event in
                self?.handle(event)
            }
            self.bridge = bridge

            let sink = RtcRemoteVideoSink { [weak self] uid, channelID, frame in
                guard let self else { return }
                let callback = platform.lock.withLock {
                    !isClosed && isJoined && channelID == roomID ? frameListeners[uid] : nil
                }
                callback?(frame)
            }
            videoSink = sink
            guard platform.engine.setVideoFrameDelegate(sink) else {
                throw XmaxError(
                    code: .rtcError, message: "Failed to register RTC video frame observer")
            }

            let options = AgoraRtcChannelMediaOptions()
            options.channelProfile = .liveBroadcasting
            options.clientRoleType = .broadcaster
            options.publishCameraTrack = false
            options.publishCustomVideoTrack = false
            options.publishMicrophoneTrack = false
            options.publishCustomAudioTrack = false
            options.autoSubscribeAudio = false
            options.autoSubscribeVideo = false
            try AgoraRtcPlatform.checkResult(
                platform.engine.joinChannelEx(
                    byToken: configuration.token,
                    channelId: roomID,
                    userAccount: configuration.userID,
                    delegate: bridge,
                    mediaOptions: options,
                    joinSuccess: nil
                ),
                operation: "joinChannelEx"
            )
        }
    }

    /// 停止回调、清理信令和帧监听，并离开房间；重复调用无副作用。
    func destroy() {
        platform.lock.withLock {
            guard !isClosed else { return }
            isClosed = true
            isJoined = false
            listener = nil
            sender?.close()
            sender = nil
            frameListeners.removeAll()
            accounts.removeAll()
            publications.removeAll()

            if let account {
                platform.engine.setVideoFrameDelegate(nil)
                _ = platform.engine.leaveChannelEx(
                    roomID, userAccount: account, leaveChannelBlock: nil)
            }
            bridge = nil
            videoSink = nil
        }
    }

    /// 更新本地视频发布状态。
    ///
    /// - Parameter publish: 是否发布外部视频轨。
    /// - Throws: 发布配置失败时抛出错误。
    func publishLocalVideo(_ publish: Bool) throws {
        try platform.lock.withLock {
            try requireJoined()
            let options = AgoraRtcChannelMediaOptions()
            options.publishCameraTrack = false
            options.publishCustomVideoTrack = publish
            options.customVideoTrackId = 0
            try update(options, operation: "publishLocalVideo")
            if publish { try platform.reapplyVideoConfiguration() }
        }
    }

    /// 更新本地音频发布状态。
    ///
    /// - Parameter publish: 是否发布当前音频源。
    /// - Throws: 发布配置失败时抛出错误。
    func publishLocalAudio(_ publish: Bool) throws {
        try platform.lock.withLock {
            try requireJoined()
            let options = AgoraRtcChannelMediaOptions()
            options.publishMicrophoneTrack = publish && platform.audioTrackID == nil
            options.publishCustomAudioTrack = publish && platform.audioTrackID != nil
            if let audioTrackID = platform.audioTrackID {
                options.publishCustomAudioTrackId = audioTrackID
            }
            try update(options, operation: "publishLocalAudio")
        }
    }

    /// 更新远端视频订阅。
    ///
    /// - Parameters:
    ///   - userID: 服务端分配的 RTC 用户账号。
    ///   - subscribe: 是否订阅视频。
    /// - Throws: 用户映射或订阅失败时抛出错误。
    func subscribeRemoteVideo(userID: String, subscribe: Bool) throws {
        try platform.lock.withLock {
            try requireJoined()
            try AgoraRtcPlatform.checkResult(
                platform.engine.muteRemoteVideoStreamEx(
                    try resolveUID(userID), mute: !subscribe, connection: connection
                ),
                operation: "subscribeRemoteVideo"
            )
        }
    }

    /// 更新远端音频订阅。
    ///
    /// - Parameters:
    ///   - userID: 服务端分配的 RTC 用户账号。
    ///   - subscribe: 是否订阅音频。
    /// - Throws: 用户映射或订阅失败时抛出错误。
    func subscribeRemoteAudio(userID: String, subscribe: Bool) throws {
        try platform.lock.withLock {
            try requireJoined()
            try AgoraRtcPlatform.checkResult(
                platform.engine.muteRemoteAudioStreamEx(
                    try resolveUID(userID), mute: !subscribe, connection: connection
                ),
                operation: "subscribeRemoteAudio"
            )
        }
    }

    /// 设置远端音频播放音量。
    ///
    /// - Parameters:
    ///   - volume: 0 到 100 的音量。
    ///   - userID: RTC 用户账号。
    /// - Throws: 用户映射或音量配置失败时抛出错误。
    func setRemoteAudioVolume(_ volume: Int, for userID: String) throws {
        try platform.lock.withLock {
            try requireJoined()
            try AgoraRtcPlatform.checkResult(
                platform.engine.adjustUserPlaybackSignalVolumeEx(
                    try resolveUID(userID), volume: volume, connection: connection
                ),
                operation: "setRemoteAudioVolume"
            )
        }
    }

    /// 设置远端解码帧监听。
    ///
    /// - Parameters:
    ///   - listener: 帧回调；传入 nil 清除监听。
    ///   - userID: RTC 用户账号。
    /// - Throws: 用户映射失败时抛出错误。
    func setRemoteVideoFrameListener(_ listener: RtcRemoteVideoFrameListener?, for userID: String)
        throws
    {
        try platform.lock.withLock {
            try requireJoined()
            frameListeners[try resolveUID(userID)] = listener
        }
    }

    /// 将信令加入房间发送队列。
    ///
    /// - Parameters:
    ///   - message: 完整 JSON 信令。
    ///   - reportFailure: 异步发送失败时是否通知房间故障；false 仅记录日志并由等待调用抛出。
    /// - Returns: 本条信令的发送任务。
    /// - Throws: 信令无效或队列不可用时抛出错误。
    @discardableResult
    func sendRoomMessage(_ message: String, reportFailure: Bool = true) throws -> Task<Void, any Error> {
        try platform.lock.withLock {
            try requireJoined()
            guard let sender else {
                throw XmaxError(code: .rtcError, message: "RTC signaling is unavailable")
            }
            return try sender.enqueue(message, reportFailure: reportFailure)
        }
    }

    /// 等待此前排队的信令提交给 RTC。
    ///
    /// - Throws: 发送失败、离房或调用取消时抛出错误。
    func awaitPendingMessages() async throws {
        let sender = try platform.lock.withLock {
            try requireJoined()
            return sender
        }
        try await sender?.flush()
    }
}

private extension AgoraRtcRoom {
    /// 将平台连接回调转换为房间事件，并在解锁后通知监听器。
    ///
    /// - Parameter event: 声网连接回调事件。
    func handle(_ event: RtcRoomEventBridge.Event) {
        let events: [RtcRoomEvent] = platform.lock.withLock {
            guard !isClosed else { return [] }
            switch event {
            case .joined(let uid):
                guard !isJoined else { return [] }
                do {
                    try prepareJoinedRoom(uid: uid)
                    return [.joined]
                        + publications.compactMap { uid, published in
                            publicationEvent(uid: uid, published: published)
                        }
                } catch {
                    return [.failure(XmaxError.from(error))]
                }
            case .account(let uid, let account):
                accounts[uid] = account
                return publicationEvents(uid: uid)
            case .userJoined(let uid):
                resolveAccount(uid: uid)
                return publicationEvents(uid: uid)
            case .publication(let uid, let published):
                publications[uid] = published
                resolveAccount(uid: uid)
                return publicationEvents(uid: uid)
            case .failure(let message):
                return [.failure(XmaxError(code: .rtcError, message: message))]
            case .quality(let up, let down):
                return [
                    .quality(
                        uplink: RtcQualityConverter.convertLevel(up),
                        downlink: RtcQualityConverter.convertLevel(down)
                    )
                ]
            case .localStats(let stats):
                let statistics = RtcQualityConverter.uplinkVideoStatistics(stats)
                RtcStatsLogger.logUplinkVideoStatistics(statistics)
                let adaptation = stats.qualityAdaptIndication.rawValue
                let events: [RtcRoomEvent] = [.uplinkVideoStatistics(statistics)]
                guard adaptation == 1 || adaptation == 2 else { return events }
                return events + [
                    .performance(
                        limited: adaptation == 2,
                        width: stats.encodedFrameWidth,
                        height: stats.encodedFrameHeight,
                        frameRate: stats.encoderOutputFrameRate
                    )
                ]
            case .remoteStats(let stats):
                resolveAccount(uid: stats.uid)
                guard let account = accounts[stats.uid] else { return [] }
                let statistics = RtcQualityConverter.downlinkVideoStatistics(userID: account, stats)
                RtcStatsLogger.logDownlinkVideoStatistics(statistics)
                return [.downlinkVideoStatistics(statistics)]
            }
        }

        // 离开平台锁后再通知生命周期层，避免与调用方向形成反向持锁。
        for event in events { emit(event) }
    }

    /// 建立有序信令通道并完成房间初始化。
    ///
    /// - Parameter uid: 本地用户的数字标识。
    /// - Throws: 信令数据通道创建失败时抛出错误。
    func prepareJoinedRoom(uid: UInt) throws {
        connection.localUid = uid
        let config = AgoraDataStreamConfig()
        config.ordered = true
        config.syncWithAudio = false
        try AgoraRtcPlatform.checkResult(
            platform.engine.createDataStreamEx(
                &dataStreamID, config: config, connection: connection),
            operation: "createDataStreamEx"
        )
        sender = RtcMessageQueue(
            send: { [weak self] data in
                guard let self else { throw CancellationError() }
                try platform.lock.withLock {
                    try requireJoined()
                    try AgoraRtcPlatform.checkResult(
                        platform.engine.sendStreamMessageEx(
                            dataStreamID, data: data, connection: connection),
                        operation: "sendStreamMessageEx"
                    )
                }
            },
            onFailure: { [weak self] error in self?.emit(.failure(error)) }
        )
        isJoined = true
    }

    /// 向仍有效的房间监听器发送事件。
    ///
    /// - Parameter event: 待通知的房间事件。
    func emit(_ event: RtcRoomEvent) {
        let callback = platform.lock.withLock { isClosed ? nil : listener }
        callback?(event)
    }

    /// 获取已知用户的当前视频发布事件。
    ///
    /// - Parameter uid: 远端用户数字标识。
    /// - Returns: 可解析的发布事件；状态或账号不可用时返回空数组。
    func publicationEvents(uid: UInt) -> [RtcRoomEvent] {
        guard let published = publications[uid],
            let event = publicationEvent(uid: uid, published: published)
        else { return [] }
        return [event]
    }

    /// 将数字用户发布状态转换为账号事件。
    ///
    /// - Parameters:
    ///   - uid: 远端用户数字标识。
    ///   - published: 视频是否已发布。
    /// - Returns: 账号可用且已进房时返回发布事件，否则返回 `nil`。
    func publicationEvent(uid: UInt, published: Bool) -> RtcRoomEvent? {
        guard isJoined, let account = accounts[uid] else { return nil }
        return .publication(userID: account, published: published)
    }

    /// 从平台补全尚未缓存的用户账号。
    ///
    /// - Parameter uid: 远端用户数字标识。
    func resolveAccount(uid: UInt) {
        guard accounts[uid] == nil else { return }
        accounts[uid] =
            platform.engine.getUserInfo(
                byUidEx: uid, connection: connection, withError: nil
            )?.userAccount
    }

    /// 从缓存或平台查询用户账号对应的数字标识。
    ///
    /// - Parameter account: 远端用户账号。
    /// - Returns: 账号对应的数字用户标识。
    /// - Throws: 账号映射不可用时抛出错误。
    func resolveUID(_ account: String) throws -> UInt {
        if let uid = accounts.first(where: { $0.value == account })?.key { return uid }
        if let info = platform.engine.getUserInfo(
            byUserAccountEx: account, connection: connection, withError: nil
        ) {
            accounts[info.uid] = account
            return info.uid
        }
        throw XmaxError(code: .rtcError, message: "RTC user account is not available: \(account)")
    }

    /// 校验房间尚未关闭且已完成连接。
    ///
    /// - Throws: 房间未连接或已关闭时抛出错误。
    func requireJoined() throws {
        guard !isClosed, isJoined else {
            throw XmaxError(code: .rtcError, message: "RTC room is not joined")
        }
    }

    /// 更新当前连接的媒体选项。
    ///
    /// - Parameters:
    ///   - options: 待应用的发布或订阅配置。
    ///   - operation: 用于错误描述的操作名称。
    /// - Throws: 平台更新配置失败时抛出错误。
    func update(_ options: AgoraRtcChannelMediaOptions, operation: String) throws {
        try AgoraRtcPlatform.checkResult(
            platform.engine.updateChannelEx(with: options, connection: connection),
            operation: operation
        )
    }
}
