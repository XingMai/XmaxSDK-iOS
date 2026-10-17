//
//  StreamController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

typealias RemoteStreamListener = @MainActor @Sendable (
    RemoteStream?
) throws -> Void

/// 统一协调 RTC 房间、媒体流、编码和质量事件。
final class StreamController: StreamControlling, RtcEventListener,
    @unchecked Sendable {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 传输层组件
    private let roomController: any RoomControlling
    private let encodingController: any EncodingControlling
    private let qualityController: any QualityControlling

    // 事件监听
    private let errorListener: XmaxErrorListener
    private let remoteStreamListener: RemoteStreamListener

    // 生成配置
    private let generationTiming: StreamGenerationTiming

    // 耗时统计
    private let timing: RealtimeTiming

    // 音频配置
    private var remoteAudioVolumePercentage = 100

    // 并发控制
    private let stateLock = NSLock()
    private let operationLock = NSRecursiveLock()

    // 运行状态
    private var state = State()

    var hasGenerationTask: Bool {
        stateLock.withLock { state.generationTask != nil }
    }

    var remoteAudioVolume: Float {
        Float(stateLock.withLock { remoteAudioVolumePercentage }) / 100
    }

    convenience init(
        rtcManager: any RtcManaging,
        errorListener: @escaping XmaxErrorListener = { _ in },
        remoteStreamListener: @escaping RemoteStreamListener = { _ in },
        generationTiming: StreamGenerationTiming = .live,
        timing: RealtimeTiming = RealtimeTiming()
    ) {
        self.init(
            rtcManager: rtcManager,
            roomController: RoomController(
                rtcManager: rtcManager,
                timing: timing
            ),
            encodingController: EncodingController(rtcManager: rtcManager),
            qualityController: QualityController(rtcManager: rtcManager),
            errorListener: errorListener,
            remoteStreamListener: remoteStreamListener,
            generationTiming: generationTiming,
            timing: timing
        )
    }

    init(
        rtcManager: any RtcManaging,
        roomController: any RoomControlling,
        encodingController: any EncodingControlling,
        qualityController: any QualityControlling,
        errorListener: @escaping XmaxErrorListener = { _ in },
        remoteStreamListener: @escaping RemoteStreamListener = { _ in },
        generationTiming: StreamGenerationTiming = .live,
        timing: RealtimeTiming = RealtimeTiming()
    ) {
        self.rtcManager = rtcManager
        self.roomController = roomController
        self.encodingController = encodingController
        self.qualityController = qualityController
        self.errorListener = errorListener
        self.remoteStreamListener = remoteStreamListener
        self.generationTiming = generationTiming
        self.timing = timing
        rtcManager.setEventListener(self)
    }

    func setVideoEncoderConfig(
        _ videoFormat: RealtimeVideoFormat
    ) throws {
        try encodingController.configure(videoFormat)
    }

    var qualityConfiguration: QualityConfiguration? { qualityController.qualityConfiguration }

    func prepareQuality(baseline: RealtimeVideoFormat, model: String) -> QualityConfiguration {
        qualityController.prepareQuality(baseline: baseline, model: model)
    }

    func setAdaptiveQualityListener(_ listener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?) {
        qualityController.setAdaptiveQualityListener(listener)
    }

    func proposeQuality(_ quality: RealtimeNetworkQuality, sampledAt: TimeInterval) -> QualityChange {
        qualityController.proposeQuality(quality, sampledAt: sampledAt)
    }

    func completeQuality(downlink: Bool, level: Int, success: Bool) {
        qualityController.completeQuality(downlink: downlink, level: level, success: success)
    }

    func resetQualitySamples() { qualityController.resetQualitySamples() }

    func setUplinkVideoStatisticsListener(_ listener: UplinkVideoStatisticsListener?) {
        qualityController.setUplinkVideoStatisticsListener(listener)
    }

    func setDownlinkVideoStatisticsListener(_ listener: DownlinkVideoStatisticsListener?) {
        qualityController.setDownlinkVideoStatisticsListener(listener)
    }

    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) {
        qualityController.setNetworkQualityListener(listener)
    }

    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) {
        qualityController.setPerformanceAlarmListener(listener)
    }

    func setRemoteAudioVolume(_ volume: Float) throws {
        let rtcVolume = Int((volume * 100).rounded())
        try operationLock.withLock {
            let userIDs = stateLock.withLock {
                state.subscribedRemoteAudioUserIDs.sorted()
            }
            for userID in userIDs {
                try rtcManager.setRemoteAudioVolume(
                    rtcVolume,
                    for: userID
                )
            }
            stateLock.withLock {
                remoteAudioVolumePercentage = rtcVolume
            }
        }
    }

    func connect(
        connection: RealtimeSessionConnection,
        includeLocalAudio: Bool,
        ensureActive: @escaping @Sendable () throws -> Void
    ) async throws {
        try ensureActive()
        try configureRoom(roomID: connection.roomID, botName: connection.botName)
        try await roomController.join(
            connection: connection,
            ensureActive: ensureActive
        )
        try ensureActive()
        timing.beginLocalPublication()
        try publishLocalStream(includeAudio: includeLocalAudio)
        timing.finishLocalPublication()
    }

    func disconnect() async {
        qualityController.resetQuality()
        await resetStream()
        await roomController.leave()
    }

    func beginGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        context: RealtimeContext,
        faceRestoration: Bool = false,
        paddingContain: Bool = false
    ) async throws -> Task<Void, any Error> {
        timing.beginSignal(taskID: taskID)
        let confirmation = try beginGenerationConfirmation(taskID: taskID)
        do {
            try await roomController.startGeneration(
                taskID: taskID,
                videoFormat: videoFormat,
                targetSize: targetSize,
                context: context,
                faceRestoration: faceRestoration,
                paddingContain: paddingContain
            )
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.rtcManager.awaitPendingMessages() }
                group.addTask {
                    try await Task.sleep(nanoseconds: self.generationTiming.timeoutNanoseconds)
                    throw XmaxError(code: .timeout, message: "Realtime generation start timed out")
                }
                defer { group.cancelAll() }
                try await group.next()
            }
            try Task.checkCancellation()
            await confirmPublishedRemoteStream(taskID: taskID)
            return confirmation
        } catch {
            confirmation.cancel()
            try? await stopGeneration(taskID: taskID)
            throw XmaxError.from(error)
        }
    }

    func activateRemoteAudio() throws {
        try operationLock.withLock {
            let remoteStream: RemoteStream? = stateLock.withLock {
                guard state.generationTask != nil else { return nil }
                return state.activeRemoteStream
            }
            guard let remoteStream else {
                throw XmaxError(
                    code: .rtcError,
                    message: "Remote generation audio stream is unavailable"
                )
            }
            try subscribeRemoteAudio(userID: remoteStream.userID)
        }
    }

    func updateGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        context: RealtimeContext,
        faceRestoration: Bool = false,
        paddingContain: Bool = false
    ) async throws {
        try await roomController.changeGenerationCondition(
            taskID: taskID,
            videoFormat: videoFormat,
            targetSize: targetSize,
            context: context,
            faceRestoration: faceRestoration,
                paddingContain: paddingContain
        )
    }

    func stopGeneration(taskID: String) async throws {
        let stoppedTaskID = await stopStreamGeneration(taskID: taskID)
        guard taskID.isEmpty || !stoppedTaskID.isEmpty else {
            return
        }
        try await roomController.stopGeneration(taskID: stoppedTaskID)
    }

    func sendTracks(
        taskID: String,
        points: [RealtimePoint]
    ) async throws {
        try await roomController.sendTracks(
            taskID: taskID,
            points: points
        )
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
                    qualityController.setUplinkVideoStatisticsEnabled(true)
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

    func pushLocalVideoFrame(_ frame: VideoFrame) throws {
        guard stateLock.withLock({ state.generationTask != nil }) else {
            return
        }
        do {
            try rtcManager.pushExternalVideoFrame(frame)
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

    func changeTargetSize(
        taskID: String,
        targetSize: CGSize,
        ensureActive: @escaping @Sendable () throws -> Void
    ) async throws {
        try await roomController.changeTargetSize(
            taskID: taskID,
            targetSize: targetSize,
            ensureActive: ensureActive
        )
    }

    func beginGenerationConfirmation(
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

    @discardableResult
    func stopStreamGeneration(
        taskID: String,
        reason: String = "Realtime generation start cancelled"
    ) async -> String {
        let result = operationLock.withLock { () -> StopResult? in
            let currentTaskID = stateLock.withLock {
                state.generationTask?.id ?? ""
            }
            guard taskID.isEmpty || taskID == currentTaskID else {
                return nil
            }

            let stoppedState = stateLock.withLock { () -> (
                GenerationWaiter?,
                Set<String>
            ) in
                let waiter = state.generationWaiter
                let remoteAudioUserIDs =
                    state.subscribedRemoteAudioUserIDs
                state.generationTask = nil
                state.generationWaiter = nil
                state.activeRemoteStream = nil
                state.subscribedRemoteAudioUserIDs.removeAll()
                return (waiter, remoteAudioUserIDs)
            }
            return StopResult(
                taskID: currentTaskID,
                waiter: stoppedState.0,
                remoteAudioUserIDs: stoppedState.1
            )
        }
        guard let result else {
            return ""
        }

        reject(
            result.waiter,
            error: XmaxError(code: .cancelled, message: reason)
        )
        for userID in result.remoteAudioUserIDs.sorted() {
            performCleanup("取消订阅 RTC 远端音频失败 (Failed to Unsubscribe from RTC Remote Audio)") {
                try rtcManager.subscribeRemoteAudio(
                    userID: userID,
                    subscribe: false
                )
            }
        }
        await clearRemoteStream()
        return result.taskID
    }

    func resetStream() async {
        qualityController.setUplinkVideoStatisticsEnabled(false)
        _ = await stopStreamGeneration(taskID: "")
        operationLock.withLock {
            let previousState = stateLock.withLock { () -> State in
                let previousState = state
                state = State()
                return previousState
            }

            for userID in previousState.subscribedRemoteUserIDs.sorted() {
                performCleanup("取消订阅 RTC 远端视频失败 (Failed to Unsubscribe from RTC Remote Video)") {
                    try rtcManager.subscribeRemoteVideo(
                        userID: userID,
                        subscribe: false
                    )
                }
            }
            if previousState.localAudioPublished {
                performCleanup("取消发布 RTC 本地音频失败 (Failed to Unpublish RTC Local Audio)") {
                    try rtcManager.unpublishLocalAudio()
                }
            }
            if previousState.localVideoPublished {
                performCleanup("取消发布 RTC 本地视频失败 (Failed to Unpublish RTC Local Video)") {
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
                confirmRemoteStream(RemoteStream(roomID: currentState.roomID, userID: userID))
            } else {
                _ = stateLock.withLock {
                    state.subscribedRemoteUserIDs.remove(userID)
                }
                if currentState.activeRemoteStream?.userID == userID {
                    unsubscribeRemoteAudio(userID: userID)
                    stateLock.withLock {
                        state.activeRemoteStream = nil
                    }
                    clearRemoteStream()
                }
            }
        }
    }

    @MainActor
    func onRtcFailure(_ error: XmaxError) {
        let taskID = stateLock.withLock { state.generationWaiter?.taskID }
        if let taskID {
            rejectGenerationStart(taskID: taskID, error: error)
        } else {
            errorListener(error)
        }
    }
}

private extension StreamController {
    @MainActor
    func confirmPublishedRemoteStream(taskID: String) {
        let stream = stateLock.withLock { () -> RemoteStream? in
            guard let waiter = state.generationWaiter, waiter.taskID == taskID else { return nil }
            waiter.signalSent = true
            guard let userID = state.subscribedRemoteUserIDs.first(where: {
                state.botName.isEmpty || $0 == state.botName
            }) else { return nil }
            return RemoteStream(roomID: state.roomID, userID: userID)
        }
        if let stream { confirmRemoteStream(stream) }
    }

    @MainActor
    func confirmRemoteStream(_ stream: RemoteStream) {
        let waiter = operationLock.withLock { () -> GenerationWaiter? in
            stateLock.withLock {
                guard state.generationTask != nil,
                      let waiter = state.generationWaiter,
                      waiter.signalSent,
                      !waiter.confirmationPending,
                      state.subscribedRemoteUserIDs.contains(stream.userID),
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
                    qualityController.setDownlinkVideoStatisticsUser(stream.userID)
                }
            }
        } catch {
            rejectGenerationStart(
                taskID: waiter.taskID,
                error: XmaxError.from(error)
            )
            return
        }

        resolveGenerationStart(taskID: waiter.taskID)
    }
}

private extension StreamController {
    struct State {
        var roomID = ""
        var botName = ""
        var localVideoPublished = false
        var localAudioPublished = false
        var subscribedRemoteUserIDs: Set<String> = []
        var subscribedRemoteAudioUserIDs: Set<String> = []
        var generationTask: GenerationTask?
        var generationWaiter: GenerationWaiter?
        var activeRemoteStream: RemoteStream?
    }

    struct GenerationTask {
        let id: String
    }

    final class GenerationWaiter: @unchecked Sendable {
        let taskID: String
        let continuation: AsyncThrowingStream<Void, any Error>.Continuation
        var timeoutTask: Task<Void, Never>?
        var confirmationPending = false
        var signalSent = false

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
        let remoteAudioUserIDs: Set<String>
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
            let xmaxError = XmaxError.from(error)
            let pendingTaskID = stateLock.withLock {
                state.generationWaiter == nil
                    ? nil
                    : state.generationTask?.id
            }
            if let pendingTaskID {
                rejectGenerationStart(
                    taskID: pendingTaskID,
                    error: xmaxError
                )
            } else {
                errorListener(xmaxError)
            }
        }
    }

    func subscribeRemoteAudio(userID: String) throws {
        let audioState = stateLock.withLock {
            (
                state.subscribedRemoteAudioUserIDs.contains(userID),
                remoteAudioVolumePercentage
            )
        }
        guard !audioState.0 else {
            return
        }

        try rtcManager.setRemoteAudioVolume(
            audioState.1,
            for: userID
        )
        try rtcManager.subscribeRemoteAudio(
            userID: userID,
            subscribe: true
        )
        _ = stateLock.withLock {
            state.subscribedRemoteAudioUserIDs.insert(userID)
        }
    }

    func unsubscribeRemoteAudio(userID: String) {
        let wasSubscribed = stateLock.withLock {
            state.subscribedRemoteAudioUserIDs.remove(userID) != nil
        }
        guard wasSubscribed else {
            return
        }
        performCleanup("取消订阅 RTC 远端音频失败 (Failed to Unsubscribe from RTC Remote Audio)") {
            try rtcManager.subscribeRemoteAudio(
                userID: userID,
                subscribe: false
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
        waiter.continuation.finish(throwing: error)
    }

    @MainActor
    func clearRemoteStream() {
        qualityController.setDownlinkVideoStatisticsUser(nil)
        do {
            try remoteStreamListener(nil)
        } catch {
            XmaxLogger.stream.error(
                message: "清理 RTC 远端生成流失败 (Failed to Clean Up RTC Remote Generation Stream)\n" +
                    "└─ \(XmaxLogger.localized("原因：", "Reason: "))" +
                    (error as NSError).localizedDescription
            )
        }
    }

    func rollbackLocalVideoPublication() {
        qualityController.setUplinkVideoStatisticsEnabled(false)
        do {
            try rtcManager.unpublishLocalVideo()
            stateLock.withLock {
                state.localVideoPublished = false
            }
        } catch {
            XmaxLogger.stream.error(
                message: "回滚 RTC 本地视频发布失败 (Failed to Roll Back RTC Local Video Publication)\n" +
                    "└─ \(XmaxLogger.localized("原因：", "Reason: "))" +
                    (error as NSError).localizedDescription
            )
        }
    }

    func performCleanup(
        _ title: String,
        action: () throws -> Void
    ) {
        do {
            try action()
        } catch {
            XmaxLogger.stream.error(
                message: "\(title)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))" +
                    (error as NSError).localizedDescription
            )
        }
    }
}

/// 定义生成确认等待的超时时间。
struct StreamGenerationTiming: Sendable {
    let timeoutNanoseconds: UInt64

    static let live = StreamGenerationTiming(
        timeoutNanoseconds: 30_000_000_000
    )
}
