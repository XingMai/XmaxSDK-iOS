import Foundation

typealias RemoteStreamListener = @MainActor @Sendable (
    RemoteStream?
) throws -> Void

/// 管理本地媒体发布、外部帧推送和远端生成流匹配。
final class StreamController: StreamControlling, RtcEventListener,
    @unchecked Sendable {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 事件监听
    private let remoteStreamListener: RemoteStreamListener

    // 生成配置
    private let generationTiming: StreamGenerationTiming

    // 并发控制
    private let stateLock = NSLock()
    private let operationLock = NSRecursiveLock()

    // 运行状态
    private var state = State()

    init(
        rtcManager: any RtcManaging,
        remoteStreamListener: @escaping RemoteStreamListener = { _ in },
        generationTiming: StreamGenerationTiming = .live
    ) {
        self.rtcManager = rtcManager
        self.remoteStreamListener = remoteStreamListener
        self.generationTiming = generationTiming
        rtcManager.setEventListener(self)
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
                      state.subscribedRemoteUserIDs.isEmpty,
                      state.generationTask == nil else {
                    throw XmaxError(
                        code: .invalidConfiguration,
                        message: "Reset the current RTC room before " +
                            "configuring another one"
                    )
                }
                state.roomID = roomID
                state.botName = botName
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
                    try rtcManager.publishLocalVideo()
                    stateLock.withLock {
                        state.localVideoPublished = true
                    }
                    publishedVideoInOperation = true
                }

                if includeAudio && !currentState.localAudioPublished {
                    try rtcManager.publishLocalAudio()
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
                    try rtcManager.publishLocalAudio()
                } else {
                    try rtcManager.unpublishLocalAudio()
                }
                stateLock.withLock {
                    state.localAudioPublished = enabled
                }
            } catch {
                throw XmaxError.from(error)
            }
        }
    }

    func pushLocalVideoFrame(_ frame: VideoFrame) throws {
        let seiData = stateLock.withLock { state.generationTask?.seiData }
        do {
            try rtcManager.pushExternalVideoFrame(frame, seiData: seiData)
        } catch {
            throw XmaxError.from(error)
        }
    }

    func pushLocalAudioFrame(_ frame: AudioFrame) throws {
        guard stateLock.withLock({ state.localAudioPublished }) else {
            return
        }
        do {
            try rtcManager.pushExternalAudioFrame(frame)
        } catch {
            throw XmaxError.from(error)
        }
    }

    func beginGeneration(
        taskID: String
    ) throws -> Task<Void, any Error> {
        let taskID = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskID.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Realtime generation task ID cannot be empty"
            )
        }

        return try operationLock.withLock {
            let currentState = stateLock.withLock { state }
            guard !currentState.roomID.isEmpty else {
                throw XmaxError(
                    code: .rtcError,
                    message: "RTC room is not configured"
                )
            }
            guard currentState.generationTask == nil else {
                throw XmaxError(
                    code: .rtcError,
                    message: "Realtime generation is already active"
                )
            }

            var continuation:
                AsyncThrowingStream<Void, any Error>.Continuation?
            let stream = AsyncThrowingStream<Void, any Error> {
                continuation = $0
            }
            guard let continuation else {
                throw XmaxError(
                    code: .internalError,
                    message: "Failed to create generation confirmation"
                )
            }
            let waiter = GenerationWaiter(
                taskID: taskID,
                continuation: continuation
            )
            stateLock.withLock {
                state.generationTask = GenerationTask(id: taskID)
                state.generationWaiter = waiter
            }
            waiter.timeoutTask = Task { [weak self, weak waiter] in
                guard let self, let waiter else {
                    return
                }
                do {
                    try await Task.sleep(
                        nanoseconds: self.generationTiming.timeoutNanoseconds
                    )
                } catch {
                    return
                }
                self.rejectGenerationStart(
                    taskID: waiter.taskID,
                    error: XmaxError(
                        code: .timeout,
                        message: "Realtime generation start timed out"
                    )
                )
            }

            return Task { [weak self] in
                try await withTaskCancellationHandler {
                    for try await _ in stream {
                        return
                    }
                } onCancel: {
                    self?.rejectGenerationStart(
                        taskID: taskID,
                        error: XmaxError(
                            code: .cancelled,
                            message: "Realtime generation start cancelled"
                        )
                    )
                }
            }
        }
    }

    @MainActor
    @discardableResult
    func stopGeneration(
        taskID: String,
        reason: String
    ) -> String {
        let result = operationLock.withLock { () -> StopResult in
            let currentTaskID = stateLock.withLock {
                state.generationTask?.id ?? ""
            }
            guard taskID.isEmpty || taskID == currentTaskID else {
                return StopResult(taskID: "", waiter: nil)
            }

            let waiter = stateLock.withLock { () -> GenerationWaiter? in
                let waiter = state.generationWaiter
                state.generationTask = nil
                state.generationWaiter = nil
                state.activeRemoteStream = nil
                return waiter
            }
            return StopResult(taskID: currentTaskID, waiter: waiter)
        }

        reject(
            result.waiter,
            error: XmaxError(code: .cancelled, message: reason)
        )
        clearRemoteStream()
        return result.taskID
    }

    @MainActor
    func resetRoom() {
        _ = stopGeneration()
        operationLock.withLock {
            let previousState = stateLock.withLock { () -> State in
                let previousState = state
                state = State()
                return previousState
            }

            for userID in previousState.subscribedRemoteUserIDs.sorted() {
                performCleanup("取消订阅 RTC 远端视频") {
                    try rtcManager.subscribeRemoteVideo(
                        userID: userID,
                        subscribe: false
                    )
                }
            }
            if previousState.localAudioPublished {
                performCleanup("取消发布 RTC 本地音频") {
                    try rtcManager.unpublishLocalAudio()
                }
            }
            if previousState.localVideoPublished {
                performCleanup("取消发布 RTC 本地视频") {
                    try rtcManager.unpublishLocalVideo()
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
                if currentState.activeRemoteStream?.userID == userID {
                    stateLock.withLock {
                        state.activeRemoteStream = nil
                    }
                    clearRemoteStream()
                }
            }
        }
    }

    @MainActor
    func onSeiMessageReceived(
        stream: RemoteStream,
        message: String
    ) {
        let waiter = operationLock.withLock { () -> GenerationWaiter? in
            stateLock.withLock {
                guard let task = state.generationTask,
                      let waiter = state.generationWaiter,
                      !waiter.confirmationPending,
                      message.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ) == task.id,
                      stream.roomID == state.roomID,
                      state.botName.isEmpty ||
                        stream.userID == state.botName else {
                    return nil
                }
                waiter.confirmationPending = true
                return waiter
            }
        }
        guard let waiter else {
            return
        }

        do {
            try remoteStreamListener(stream)
            stateLock.withLock {
                if state.generationTask?.id == waiter.taskID {
                    state.activeRemoteStream = stream
                }
            }
        } catch {
            rejectGenerationStart(
                taskID: waiter.taskID,
                error: XmaxError.from(error)
            )
            return
        }

        waiter.confirmationTask = Task { [weak self, weak waiter] in
            guard let self, let waiter else {
                return
            }
            do {
                try await Task.sleep(
                    nanoseconds: self.generationTiming
                        .confirmationDelayNanoseconds
                )
            } catch {
                return
            }
            self.resolveGenerationStart(taskID: waiter.taskID)
        }
    }
}

private extension StreamController {
    struct State {
        var roomID = ""
        var botName = ""
        var localVideoPublished = false
        var localAudioPublished = false
        var subscribedRemoteUserIDs: Set<String> = []
        var generationTask: GenerationTask?
        var generationWaiter: GenerationWaiter?
        var activeRemoteStream: RemoteStream?
    }

    struct GenerationTask {
        let id: String
        let seiData: Data

        init(id: String) {
            self.id = id
            seiData = Data(id.utf8)
        }
    }

    final class GenerationWaiter: @unchecked Sendable {
        let taskID: String
        let continuation: AsyncThrowingStream<Void, any Error>.Continuation
        var timeoutTask: Task<Void, Never>?
        var confirmationTask: Task<Void, Never>?
        var confirmationPending = false

        init(
            taskID: String,
            continuation:
                AsyncThrowingStream<Void, any Error>.Continuation
        ) {
            self.taskID = taskID
            self.continuation = continuation
        }
    }

    struct StopResult {
        let taskID: String
        let waiter: GenerationWaiter?
    }

    func subscribeRemoteVideo(userID: String) {
        let alreadySubscribed = stateLock.withLock {
            state.subscribedRemoteUserIDs.contains(userID)
        }
        guard !alreadySubscribed else {
            return
        }

        do {
            try rtcManager.subscribeRemoteVideo(
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

    func resolveGenerationStart(taskID: String) {
        let waiter = operationLock.withLock { () -> GenerationWaiter? in
            stateLock.withLock {
                guard state.generationTask?.id == taskID,
                      state.generationWaiter?.taskID == taskID else {
                    return nil
                }
                let waiter = state.generationWaiter
                state.generationWaiter = nil
                return waiter
            }
        }
        guard let waiter else {
            return
        }
        waiter.timeoutTask?.cancel()
        waiter.confirmationTask?.cancel()
        waiter.continuation.yield()
        waiter.continuation.finish()
    }

    func rejectGenerationStart(
        taskID: String,
        error: XmaxError
    ) {
        let waiter = operationLock.withLock { () -> GenerationWaiter? in
            stateLock.withLock {
                guard state.generationTask?.id == taskID,
                      state.generationWaiter?.taskID == taskID else {
                    return nil
                }
                let waiter = state.generationWaiter
                state.generationWaiter = nil
                return waiter
            }
        }
        reject(waiter, error: error)
    }

    func reject(
        _ waiter: GenerationWaiter?,
        error: XmaxError
    ) {
        guard let waiter else {
            return
        }
        waiter.timeoutTask?.cancel()
        waiter.confirmationTask?.cancel()
        waiter.continuation.finish(throwing: error)
    }

    @MainActor
    func clearRemoteStream() {
        do {
            try remoteStreamListener(nil)
        } catch {
            XmaxLogger.error(
                "清理 RTC 远端生成流失败\n└─ 原因：" +
                    (error as NSError).localizedDescription,
                category: "Stream"
            )
        }
    }

    func rollbackLocalVideoPublication() {
        do {
            try rtcManager.unpublishLocalVideo()
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

/// 定义生成确认等待的超时和远端首帧稳定延迟。
struct StreamGenerationTiming: Sendable {
    let timeoutNanoseconds: UInt64
    let confirmationDelayNanoseconds: UInt64

    static let live = StreamGenerationTiming(
        timeoutNanoseconds: 30_000_000_000,
        confirmationDelayNanoseconds: 150_000_000
    )
}
