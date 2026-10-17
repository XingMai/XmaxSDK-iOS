//
//  StreamController.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 在主线程更新远端结果流绑定，空值表示清除绑定。
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


    // 生成状态查询
    var hasGenerationTask: Bool {
        stateLock.withLock { state.generationTask != nil }
    }


    // 远端音量查询
    var remoteAudioVolume: Float {
        Float(stateLock.withLock { remoteAudioVolumePercentage }) / 100
    }

    /// 创建房间、编码和质量组件组成的流控制器。
    ///
    /// - Parameters:
    ///   - rtcManager: 底层 RTC 管理器。
    ///   - errorListener: 接收流运行错误的回调。
    ///   - remoteStreamListener: 接收远端结果流绑定变化的回调。
    ///   - generationTiming: 结果流确认等待的超时配置。
    ///   - timing: 共享的实时启动耗时记录器。
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

    /// 使用指定组件创建流控制器并注册 RTC 事件监听。
    ///
    /// - Parameters:
    ///   - rtcManager: 底层 RTC 管理器。
    ///   - roomController: 房间连接和信令组件。
    ///   - encodingController: 视频编码配置组件。
    ///   - qualityController: 网络质量和调档组件。
    ///   - errorListener: 接收流运行错误的回调。
    ///   - remoteStreamListener: 接收远端结果流绑定变化的回调。
    ///   - generationTiming: 结果流确认等待的超时配置。
    ///   - timing: 共享的实时启动耗时记录器。
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

    /// 设置实时视频编码器配置。
    ///
    /// - Parameter videoFormat: RTC 视频编码使用的宽度、高度和帧率。
    /// - Throws: 视频格式无效或 RTC 编码配置失败时抛出错误。
    func setVideoEncoderConfig(
        _ videoFormat: RealtimeVideoFormat
    ) throws {
        try encodingController.configure(videoFormat)
    }


    // 质量配置查询
    var qualityConfiguration: QualityConfiguration? { qualityController.qualityConfiguration }

    /// 根据媒体基准和模型历史准备上下行档位。
    ///
    /// - Parameters:
    ///   - baseline: 本地媒体原始输出规格，不随调档改变。
    ///   - model: 用于隔离历史档位的模型标识。
    /// - Returns: 本次连接的初始上下行配置。
    func prepareQuality(baseline: RealtimeVideoFormat, model: String) -> QualityConfiguration {
        qualityController.prepareQuality(baseline: baseline, model: model)
    }

    /// 设置内部调档采样回调，不影响公开网络质量监听。
    ///
    /// - Parameter listener: 接收网络质量及单调时钟采样时间；nil 表示移除。
    func setAdaptiveQualityListener(_ listener: (@Sendable (RealtimeNetworkQuality, TimeInterval) -> Void)?) {
        qualityController.setAdaptiveQualityListener(listener)
    }

    /// 消费当前网络采样并返回候选档位。
    ///
    /// - Parameters:
    ///   - quality: 当前上下行网络质量。
    ///   - sampledAt: 单调时钟的采样时间，单位为秒。
    /// - Returns: 满足连续采样和冷却条件的候选档位。
    func proposeQuality(_ quality: RealtimeNetworkQuality, sampledAt: TimeInterval) -> QualityChange {
        qualityController.proposeQuality(quality, sampledAt: sampledAt)
    }

    /// 提交调档结果，成功时保存历史档位。
    ///
    /// - Parameters:
    ///   - downlink: true 表示下行，false 表示上行。
    ///   - level: 本次尝试的档位，范围为 1...5。
    ///   - success: 配置是否成功应用。
    func completeQuality(downlink: Bool, level: Int, success: Bool) {
        qualityController.completeQuality(downlink: downlink, level: level, success: success)
    }

    /// 清除连续采样窗口。
    func resetQualitySamples() { qualityController.resetQualitySamples() }

    /// 设置视频上行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；未发布或断开连接时收到 nil；传入 nil 清除监听器。
    func setUplinkVideoStatisticsListener(_ listener: UplinkVideoStatisticsListener?) {
        qualityController.setUplinkVideoStatisticsListener(listener)
    }

    /// 设置视频下行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；结果流清理时收到 nil；传入 nil 清除监听器。
    func setDownlinkVideoStatisticsListener(_ listener: DownlinkVideoStatisticsListener?) {
        qualityController.setDownlinkVideoStatisticsListener(listener)
    }

    /// 设置网络质量监听器，传入空值时清除监听器。
    ///
    /// - Parameter listener: 接收上行和下行网络质量事件的监听器；
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) {
        qualityController.setNetworkQualityListener(listener)
    }

    /// 设置设备性能告警监听器，传入空值时清除监听器。
    ///
    /// - Parameter listener: 接收设备性能受限与恢复事件的监听器；
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) {
        qualityController.setPerformanceAlarmListener(listener)
    }

    /// 设置远端生成音频播放音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 `0...1` 的音量。
    /// - Throws: RTC 音量配置失败时抛出错误。
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

    /// 加入 RTC 房间并发布本地媒体流。
    ///
    /// - Parameters:
    ///   - connection: RTC 房间、用户、Token 和目标机器人信息。
    ///   - includeLocalAudio: 是否随本地视频一起发布本地音频。
    ///   - ensureActive: 在异步边界校验当前连接操作仍然有效的回调；
    /// - Throws: 连接已取消，或 RTC 进房、房间配置与本地流发布失败时
    ///   抛出错误。
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

    /// 清理生成状态、本地发布和远端订阅，并离开当前 RTC 房间；
    /// 没有活动房间时安全返回。
    func disconnect() async {
        qualityController.resetQuality()
        await resetStream()
        await roomController.leave()
    }

    /// 建立生成任务、发送开始信令并启动结果流确认等待。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务的唯一标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 生成使用的参考图、提示词等条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否按包含模式保留源比例并填充生成画布。
    /// - Returns: 等待远端结果流发布确认的任务。
    /// - Throws: 任务参数无效、房间未就绪、已有生成任务、信令失败或发送等待超时时抛出错误。
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

    /// 在远端首帧已经可显示后订阅当前生成流的音频。
    ///
    /// - Throws: 当前生成流尚未确认，或 RTC 音量和订阅配置失败时抛出错误。
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

    /// 发送当前生成任务的条件变更信令。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务的唯一标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 生成使用的参考图、提示词等条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否按包含模式保留源比例并填充生成画布。
    /// - Throws: 房间未就绪、参数无效或信令提交失败时抛出错误。
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

    /// 停止生成任务并清理远端结果流。
    ///
    /// - Parameter taskID: 需要停止的生成任务标识；传入空字符串时停止
    /// - Throws: RTC 停止信令发送失败时抛出错误。
    func stopGeneration(taskID: String) async throws {
        let stoppedTaskID = await stopStreamGeneration(taskID: taskID)
        guard taskID.isEmpty || !stoppedTaskID.isEmpty else {
            return
        }
        try await roomController.stopGeneration(taskID: stoppedTaskID)
    }

    /// 发送生成任务的交互轨迹。
    ///
    /// - Parameters:
    ///   - taskID: 接收交互轨迹的生成任务标识。
    ///   - points: 需要发送的轨迹点；空数组会被忽略。
    /// - Throws: RTC 房间未就绪、任务标识无效或轨迹信令发送失败时
    ///   抛出错误。
    func sendTracks(
        taskID: String,
        points: [RealtimePoint]
    ) async throws {
        try await roomController.sendTracks(
            taskID: taskID,
            points: points
        )
    }

    /// 校验并记录当前房间及目标机器人标识。
    ///
    /// - Parameters:
    ///   - roomID: RTC 房间标识。
    ///   - botName: 目标机器人账号；`nil` 或空值表示不限制账号。
    /// - Throws: 房间标识为空或仍存在活动媒体状态时抛出错误。
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

    /// 发布本地视频并按配置发布本地音频。
    ///
    /// - Parameter includeAudio: 是否同时发布本地音频。
    /// - Throws: 房间未配置或 RTC 媒体发布失败时抛出错误。
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

    /// 在生成任务活动期间推送本地外部视频帧；无生成任务时忽略。
    ///
    /// - Parameter frame: 已准备好交给 RTC 的本地视频帧。
    /// - Throws: RTC 资源尚未就绪或视频帧转换失败时抛出错误。
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

    /// 推送本地外部音频帧。
    ///
    /// - Parameter frame: 已准备好交给 RTC 的 PCM 音频帧；
    /// - Throws: RTC 资源尚未就绪或音频帧转换失败时抛出错误。
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

    /// 调整当前生成任务的回传尺寸，不重启生成。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - targetSize: 生成后回传的整数像素尺寸。
    ///   - ensureActive: 发送前确认当前配置操作仍有效。
    /// - Throws: 操作已取消、房间未就绪或信令发送失败时抛出错误。
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

    /// 创建一次生成结果流确认等待及其超时任务。
    ///
    /// - Parameter taskID: 需要确认的生成任务标识。
    /// - Returns: 可取消的结果流确认任务。
    /// - Throws: 任务标识无效、房间未配置、已有生成任务或等待器创建失败时抛出错误。
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

    /// 停止匹配生成任务并清除远端音频和结果流绑定。
    ///
    /// - Parameters:
    ///   - taskID: 待停止的任务标识；空字符串表示当前任务。
    ///   - reason: 用于结束确认等待的取消原因。
    /// - Returns: 被停止的任务标识；没有匹配任务时返回空字符串。
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

    /// 清空生成、发布与订阅状态并回收对应 RTC 资源。
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

    /// 接收远端用户的视频发布状态变化。
    ///
    /// - Parameters:
    ///   - userID: 远端 RTC 用户标识。
    ///   - published: 当前是否已发布视频。
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

    /// 接收导致当前 RTC 连接或信令传输无法继续的错误。
    ///
    /// - Parameter error: 连接或信令传输错误。
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
    /// 标记开始信令已发送，并确认已发布的目标结果流。
    ///
    /// - Parameter taskID: 开始信令所属的生成任务标识。
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

    /// 绑定已发布的目标结果流并结束生成确认等待。
    ///
    /// - Parameter stream: 待确认的远端结果流。
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
    /// 保存当前房间的媒体发布、订阅和生成状态。
    struct State {

        // 房间标识
        var roomID = ""
        var botName = ""


        // 本地发布
        var localVideoPublished = false
        var localAudioPublished = false


        // 远端订阅
        var subscribedRemoteUserIDs: Set<String> = []
        var subscribedRemoteAudioUserIDs: Set<String> = []


        // 生成任务
        var generationTask: GenerationTask?
        var generationWaiter: GenerationWaiter?


        // 结果流
        var activeRemoteStream: RemoteStream?
    }

    /// 标识当前活动的生成任务。
    struct GenerationTask {

        // 任务标识
        let id: String
    }

    /// 管理生成结果流确认、超时与异步通知。
    final class GenerationWaiter: @unchecked Sendable {

        // 任务标识
        let taskID: String


        // 完成通知与超时
        let continuation: AsyncThrowingStream<Void, any Error>.Continuation
        var timeoutTask: Task<Void, Never>?


        // 确认状态
        var confirmationPending = false
        var signalSent = false

        /// 创建生成结果流确认上下文。
        ///
        /// - Parameters:
        ///   - taskID: 等待结果流的生成任务标识。
        ///   - continuation: 用于完成确认等待的异步流 continuation。
        init(
            taskID: String,
            continuation:
                AsyncThrowingStream<Void, any Error>.Continuation
        ) {
            self.taskID = taskID
            self.continuation = continuation
        }
    }

    /// 保存停止生成后仍需清理的等待者与音频订阅。
    struct StopResult {

        // 停止任务
        let taskID: String
        let waiter: GenerationWaiter?


        // 待清理订阅
        let remoteAudioUserIDs: Set<String>
    }

    /// 订阅远端视频，并将失败交付给当前启动等待或错误回调。
    ///
    /// - Parameter userID: 需要订阅的远端用户账号。
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

    /// 应用当前音量后订阅远端音频。
    ///
    /// - Parameter userID: 需要订阅的远端用户账号。
    /// - Throws: 音量设置或音频订阅失败时抛出错误。
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

    /// 取消已记录的远端音频订阅。
    ///
    /// - Parameter userID: 需要取消订阅的远端用户账号。
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

    /// 成功完成匹配生成任务的结果流确认等待。
    ///
    /// - Parameter taskID: 已确认结果流的生成任务标识。
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

    /// 以错误结束匹配生成任务的结果流确认等待。
    ///
    /// - Parameters:
    ///   - taskID: 等待失败的生成任务标识。
    ///   - error: 确认失败的原因。
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

    /// 取消超时任务并以错误结束指定等待者。
    ///
    /// - Parameters:
    ///   - waiter: 需要结束的确认等待者；`nil` 时不执行操作。
    ///   - error: 返回给等待者的错误。
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

    /// 清除下行统计目标并通知远端结果流解绑。
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

    /// 撤销本次操作已发布的视频并关闭上行统计。
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

    /// 执行清理操作，并记录未能完成的清理错误。
    ///
    /// - Parameters:
    ///   - title: 用于清理失败日志的中英文标题。
    ///   - action: 需要执行的同步清理操作。
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

    // 确认超时
    let timeoutNanoseconds: UInt64


    // 默认配置
    static let live = StreamGenerationTiming(
        timeoutNanoseconds: 30_000_000_000
    )
}
