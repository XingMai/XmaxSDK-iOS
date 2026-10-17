@preconcurrency import AgoraRtcKit
import Foundation

/// 封装单次声网连接、用户映射、发布订阅和 DataStream 信令。
final class AgoraRtcRoom: RtcRoom, @unchecked Sendable {

    // 平台资源
    private let platform: AgoraRtcPlatform
    private let roomID: String
    let connection = AgoraRtcConnection()
    private var bridge: RtcRoomEventBridge?
    private var videoSink: RtcRemoteVideoSink?

    // 用户与事件
    private var listener: (@Sendable (RtcRoomEvent) -> Void)?
    private var accounts: [UInt: String] = [:]
    private var publications: [UInt: Bool] = [:]
    private var frameListeners: [UInt: RtcRemoteVideoFrameListener] = [:]

    // 信令资源
    private var dataStreamID = 0
    private var sender: RtcMessageQueue?

    // 连接状态（由 platform.lock 保护）
    private var account: String?
    private(set) var isJoined = false
    private(set) var isClosed = false

    init(platform: AgoraRtcPlatform, roomID: String) {
        self.platform = platform
        self.roomID = roomID
        connection.channelId = roomID
    }

    func setEventListener(_ listener: (@Sendable (RtcRoomEvent) -> Void)?) {
        platform.lock.withLock {
            self.listener = isClosed ? nil : listener
        }
    }

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

    func setRemoteVideoFrameListener(_ listener: RtcRemoteVideoFrameListener?, for userID: String)
        throws
    {
        try platform.lock.withLock {
            try requireJoined()
            frameListeners[try resolveUID(userID)] = listener
        }
    }

    func sendRoomMessage(_ message: String) throws {
        try platform.lock.withLock {
            try requireJoined()
            guard let sender else {
                throw XmaxError(code: .rtcError, message: "RTC signaling is unavailable")
            }
            try sender.enqueue(message)
        }
    }

    func awaitPendingMessages() async throws {
        let sender = try platform.lock.withLock {
            try requireJoined()
            return sender
        }
        try await sender?.flush()
    }
}

private extension AgoraRtcRoom {
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

    func emit(_ event: RtcRoomEvent) {
        let callback = platform.lock.withLock { isClosed ? nil : listener }
        callback?(event)
    }

    func publicationEvents(uid: UInt) -> [RtcRoomEvent] {
        guard let published = publications[uid],
            let event = publicationEvent(uid: uid, published: published)
        else { return [] }
        return [event]
    }

    func publicationEvent(uid: UInt, published: Bool) -> RtcRoomEvent? {
        guard isJoined, let account = accounts[uid] else { return nil }
        return .publication(userID: account, published: published)
    }

    func resolveAccount(uid: UInt) {
        guard accounts[uid] == nil else { return }
        accounts[uid] =
            platform.engine.getUserInfo(
                byUidEx: uid, connection: connection, withError: nil
            )?.userAccount
    }

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

    func requireJoined() throws {
        guard !isClosed, isJoined else {
            throw XmaxError(code: .rtcError, message: "RTC room is not joined")
        }
    }

    func update(_ options: AgoraRtcChannelMediaOptions, operation: String) throws {
        try AgoraRtcPlatform.checkResult(
            platform.engine.updateChannelEx(with: options, connection: connection),
            operation: operation
        )
    }
}
