import Foundation

/// 管理 RTC 房间中的本地媒体发布与远端视频订阅。
final class StreamController: StreamControlling, RtcEventListener,
    @unchecked Sendable {

    // 基础层组件
    private let rtcProvider: any RtcProviding

    // 并发控制
    private let stateLock = NSLock()
    private let operationLock = NSRecursiveLock()

    // 运行状态
    private var state = State()

    init(rtcProvider: any RtcProviding) {
        self.rtcProvider = rtcProvider
        rtcProvider.setEventListener(self)
    }

    func configureRoom(
        roomID: String,
        botName: String?
    ) throws {
        let roomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let botName = botName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !roomID.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "RTC room ID cannot be empty"
            )
        }

        try operationLock.withLock {
            try stateLock.withLock {
                guard !state.localVideoPublished,
                      !state.localAudioPublished,
                      state.subscribedRemoteUserIDs.isEmpty else {
                    throw XmaxError(
                        code: .invalidConfiguration,
                        message: "Reset the current RTC room before " +
                            "configuring another one"
                    )
                }
                state.roomID = roomID
                state.botName = botName
                state.subscribedRemoteUserIDs.removeAll()
            }
        }
    }

    func publishLocalStream(includeAudio: Bool) throws {
        try operationLock.withLock {
            let currentState = stateLock.withLock { state }
            guard !currentState.roomID.isEmpty else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Configure an RTC room before publishing " +
                        "the local stream"
                )
            }

            var publishedVideoInOperation = false
            do {
                if !currentState.localVideoPublished {
                    try rtcProvider.publishLocalVideo()
                    stateLock.withLock {
                        state.localVideoPublished = true
                    }
                    publishedVideoInOperation = true
                }

                if includeAudio && !currentState.localAudioPublished {
                    try rtcProvider.publishLocalAudio()
                    stateLock.withLock {
                        state.localAudioPublished = true
                    }
                }
            } catch {
                if publishedVideoInOperation {
                    rollbackLocalVideoPublication()
                }
                throw XmaxError.from(error)
            }
        }
    }

    func setLocalAudioEnabled(_ enabled: Bool) throws {
        try operationLock.withLock {
            let currentState = stateLock.withLock { state }
            guard !currentState.roomID.isEmpty,
                  currentState.localVideoPublished else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Publish the local video stream before " +
                        "updating local audio"
                )
            }
            guard currentState.localAudioPublished != enabled else {
                return
            }

            do {
                if enabled {
                    try rtcProvider.publishLocalAudio()
                } else {
                    try rtcProvider.unpublishLocalAudio()
                }
                stateLock.withLock {
                    state.localAudioPublished = enabled
                }
            } catch {
                throw XmaxError.from(error)
            }
        }
    }

    func resetRoom() {
        operationLock.withLock {
            let previousState = stateLock.withLock { () -> State in
                let previousState = state
                state = State()
                return previousState
            }

            for userID in previousState.subscribedRemoteUserIDs.sorted() {
                performCleanup("取消订阅 RTC 远端视频") {
                    try rtcProvider.subscribeRemoteVideo(
                        userID: userID,
                        subscribe: false
                    )
                }
            }
            if previousState.localAudioPublished {
                performCleanup("取消发布 RTC 本地音频") {
                    try rtcProvider.unpublishLocalAudio()
                }
            }
            if previousState.localVideoPublished {
                performCleanup("取消发布 RTC 本地视频") {
                    try rtcProvider.unpublishLocalVideo()
                }
            }
        }
    }

    @MainActor
    func onRemoteVideoPublished(
        userID: String,
        published: Bool
    ) {
        let userID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else {
            return
        }

        operationLock.withLock {
            let currentState = stateLock.withLock { state }
            guard !currentState.roomID.isEmpty,
                  currentState.botName.isEmpty ||
                    currentState.botName == userID else {
                return
            }

            if published {
                subscribeRemoteVideo(userID: userID)
            } else {
                _ = stateLock.withLock {
                    state.subscribedRemoteUserIDs.remove(userID)
                }
            }
        }
    }

    @MainActor
    func onSeiMessageReceived(
        stream: RemoteStream,
        message: String
    ) {
        // SEI 只参与生成任务匹配，不改变相机连接阶段的发布与订阅状态。
    }
}

private extension StreamController {
    struct State {
        var roomID = ""
        var botName = ""
        var localVideoPublished = false
        var localAudioPublished = false
        var subscribedRemoteUserIDs: Set<String> = []
    }

    func subscribeRemoteVideo(userID: String) {
        let alreadySubscribed = stateLock.withLock {
            state.subscribedRemoteUserIDs.contains(userID)
        }
        guard !alreadySubscribed else {
            return
        }

        do {
            try rtcProvider.subscribeRemoteVideo(
                userID: userID,
                subscribe: true
            )
            _ = stateLock.withLock {
                state.subscribedRemoteUserIDs.insert(userID)
            }
        } catch {
            XmaxLogger.error(
                "订阅 RTC 远端视频失败\n└─ 原因：" +
                    (error as NSError).localizedDescription,
                category: "Stream"
            )
        }
    }

    func rollbackLocalVideoPublication() {
        do {
            try rtcProvider.unpublishLocalVideo()
            stateLock.withLock {
                state.localVideoPublished = false
            }
        } catch {
            XmaxLogger.error(
                "回滚 RTC 本地视频发布失败\n└─ 原因：" +
                    (error as NSError).localizedDescription,
                category: "Stream"
            )
        }
    }

    func performCleanup(
        _ operation: String,
        action: () throws -> Void
    ) {
        do {
            try action()
        } catch {
            XmaxLogger.error(
                "\(operation)失败\n└─ 原因：" +
                    (error as NSError).localizedDescription,
                category: "Stream"
            )
        }
    }
}
