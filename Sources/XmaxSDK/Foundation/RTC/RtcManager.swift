//
//  RtcManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 管理 RTC 租约、连接等待、取消及事件有效期。
final class RtcManager: RtcManaging, @unchecked Sendable {

    /// RTC 配置
    static let joinTimeoutNanoseconds: UInt64 = 15000000000

    /// 依赖
    private let engineManager: RtcEngineManager
    private let joinTimeout: UInt64

    /// 并发控制
    private let stateLock = NSLock()
    private let operationLock = NSRecursiveLock()

    /// RTC 资源
    private var engineLease: RtcEngineLease?
    private var activeRoom: RoomContext?
    private var pendingJoin: PendingJoin?

    /// 事件监听
    private weak var eventListener: (any RtcEventListener)?
    private weak var qualityListener: (any RtcQualityListener)?

    /// 运行状态
    private var initialization: Initialization?

    /// 创建 RTC 管理器并配置进房等待时限。
    ///
    /// - Parameters:
    ///   - engineManager: 管理进程级引擎独占租约的组件。
    ///   - joinTimeoutNanoseconds: 进房超时，单位为纳秒。
    init(
        engineManager: RtcEngineManager = .shared,
        joinTimeoutNanoseconds: UInt64 = RtcManager.joinTimeoutNanoseconds
    ) {
        self.engineManager = engineManager
        joinTimeout = joinTimeoutNanoseconds
    }

    /// 获取独占的 RTC 引擎租约并完成初始化。
    ///
    /// - Throws: 等待租约被取消或 RTC 引擎初始化失败时抛出错误。
    func initialize() async throws {
        guard !Task.isCancelled else {
            throw Self.cancelledError(operation: "RTC initialization")
        }
        let waiterID = UUID()
        let initialization = stateLock.withLock { () -> Initialization? in
            guard engineLease == nil else {
                return nil
            }
            if var initialization {
                initialization.waiterIDs.insert(waiterID)
                self.initialization = initialization
                return initialization
            }

            let initialization = Initialization(
                id: UUID(),
                task: Task {
                    try await engineManager.acquire()
                },
                waiterIDs: [waiterID]
            )
            self.initialization = initialization
            return initialization
        }
        guard let initialization else {
            return
        }

        do {
            let lease = try await withTaskCancellationHandler {
                try await initialization.task.value
            } onCancel: {
                self.cancelInitializationWaiter(
                    initializationID: initialization.id,
                    waiterID: waiterID
                )
            }
            try await finishInitialization(
                initializationID: initialization.id,
                lease: lease
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            clearInitialization(id: initialization.id)
            throw Self.cancelledError(operation: "RTC initialization")
        } catch {
            clearInitialization(id: initialization.id)
            throw error
        }
    }

    /// 销毁 RTC 引擎并释放资源。
    func destroy() async {
        await leaveRoom()
        let resources = operationLock.withLock {
            stateLock.withLock { () -> (RtcEngineLease?, Initialization?) in
                let resources = (engineLease, initialization)
                engineLease = nil
                initialization = nil
                return resources
            }
        }

        resources.1?.task.cancel()
        if let lease = resources.0 {
            await engineManager.release(lease)
        }
    }

    /// 应用上传视频的编码配置。
    ///
    /// - Parameter configuration: 尺寸、帧率、码率和编码偏好。
    /// - Throws: 厂商引擎拒绝配置时抛出错误。
    func configureVideoEncoding(_ configuration: VideoEncodingConfiguration) throws {
        guard configuration.width > 0, configuration.height > 0, configuration.frameRate > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video width, height, and frame rate must be positive")
        }
        try withEngine { try $0.configureVideoEncoding(configuration) }
    }

    /// 启用外部视频输入。
    ///
    /// - Throws: 视频源配置失败时抛出错误。
    func useExternalVideoSource() throws {
        try withEngine { try $0.useExternalVideoSource() }
    }

    /// 更新上传视频镜像。
    ///
    /// - Parameter position: 当前摄像头位置。
    /// - Throws: 编码镜像配置失败时抛出错误。
    func configureLocalVideoMirror(for position: CameraPosition) throws {
        try withOptionalEngine { try $0.configureLocalVideoMirror(for: position) }
    }

    /// 切换至麦克风输入并开始采集。
    ///
    /// - Throws: 音频源切换或采集失败时抛出错误。
    func startAudioCapture() throws {
        try withEngine { try $0.startAudioCapture() }
    }

    /// 停止麦克风采集。
    ///
    /// - Throws: 厂商引擎停止采集失败时抛出错误。
    func stopAudioCapture() throws {
        try withOptionalEngine { try $0.stopAudioCapture() }
    }

    /// 启用外部 PCM 输入。
    ///
    /// - Throws: 外部音频轨创建失败时抛出错误。
    func startExternalAudioSource() throws {
        try withEngine { try $0.startExternalAudioSource() }
    }

    /// 停止外部 PCM 输入并释放音频轨。
    ///
    /// - Throws: 音频轨释放失败时抛出错误。
    func stopExternalAudioSource() throws {
        try withOptionalEngine { try $0.stopExternalAudioSource() }
    }

    /// 推送外部视频帧。
    ///
    /// - Parameter frame: SDK 中性视频帧。
    /// - Throws: 帧格式或数据无效时抛出错误。
    func pushExternalVideoFrame(_ frame: VideoFrame) throws {
        try withEngine { try $0.pushExternalVideoFrame(frame) }
    }

    /// 推送外部音频帧。
    ///
    /// - Parameter frame: 带时间戳的 10 ms PCM 数据。
    /// - Throws: 帧格式或数据无效时抛出错误。
    func pushExternalAudioFrame(_ frame: AudioFrame) throws {
        try withEngine { try $0.pushExternalAudioFrame(frame) }
    }

    /// 加入 RTC 房间并等待连接完成。
    ///
    /// - Parameter configuration: 房间、用户标识及令牌配置。
    /// - Throws: 引擎不可用、进房失败、连接超时或调用取消时抛出错误。
    func joinRoom(configuration: RoomJoinConfiguration) async throws {
        guard !configuration.roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !configuration.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw XmaxError(
                code: .invalidConfiguration, message: "RTC room ID and user account cannot be empty"
            )
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                beginJoin(id: id, configuration: configuration, continuation: continuation)
            }
        } onCancel: {
            self.failPendingJoin(id: id, error: Self.cancelledError(operation: "RTC join room"))
        }
    }

    /// 离开当前 RTC 房间。
    func leaveRoom() async {
        operationLock.withLock {
            let resources = stateLock.withLock { () -> (RoomContext?, PendingJoin?) in
                let result = (activeRoom, pendingJoin)
                activeRoom = nil
                pendingJoin = nil
                return result
            }
            resources.1?.timeoutTask?.cancel()
            resources.1?.continuation.resume(
                throwing: Self.cancelledError(operation: "RTC join room"))
            tearDownRoom(resources.1?.context)
            tearDownRoom(resources.0)
        }
    }

    /// 发布本地视频流。
    ///
    /// - Throws: 房间不可用或视频发布失败时抛出错误。
    func publishLocalVideo() throws {
        try withRoom { try $0.publishLocalVideo(true) }
    }

    /// 停止发布本地视频流。
    ///
    /// - Throws: 房间不可用或停止视频发布失败时抛出错误。
    func unpublishLocalVideo() throws {
        try withOptionalRoom { try $0.publishLocalVideo(false) }
    }

    /// 发布本地音频流。
    ///
    /// - Throws: 房间不可用或音频发布失败时抛出错误。
    func publishLocalAudio() throws {
        try withRoom { try $0.publishLocalAudio(true) }
    }

    /// 停止发布本地音频流。
    ///
    /// - Throws: 房间不可用或停止音频发布失败时抛出错误。
    func unpublishLocalAudio() throws {
        try withOptionalRoom { try $0.publishLocalAudio(false) }
    }

    /// 设置指定远端用户的视频订阅状态。
    ///
    /// - Parameters:
    ///   - userID: 远端 RTC 用户标识。
    ///   - subscribe: 是否订阅视频流。
    /// - Throws: 房间不可用、用户映射或订阅配置失败时抛出错误。
    func subscribeRemoteVideo(userID: String, subscribe: Bool) throws {
        try withRoom { try $0.subscribeRemoteVideo(userID: userID, subscribe: subscribe) }
    }

    /// 设置指定远端用户的音频订阅状态。
    ///
    /// - Parameters:
    ///   - userID: 远端 RTC 用户标识。
    ///   - subscribe: 是否订阅音频流。
    /// - Throws: 房间不可用、用户映射或订阅配置失败时抛出错误。
    func subscribeRemoteAudio(userID: String, subscribe: Bool) throws {
        try withRoom { try $0.subscribeRemoteAudio(userID: userID, subscribe: subscribe) }
    }

    /// 设置指定远端用户的音频播放音量。
    ///
    /// - Parameters:
    ///   - volume: 播放音量，范围为 0 到 100。
    ///   - userID: 远端 RTC 用户标识。
    /// - Throws: 房间不可用或音量设置失败时抛出错误。
    func setRemoteAudioVolume(_ volume: Int, for userID: String) throws {
        guard (0...100).contains(volume) else {
            throw XmaxError(
                code: .invalidConfiguration, message: "RTC audio volume must be between 0 and 100")
        }
        try withRoom { try $0.setRemoteAudioVolume(volume, for: userID) }
    }

    /// 设置指定远端流的解码帧监听器。
    ///
    /// - Parameters:
    ///   - listener: 解码帧回调；传入 `nil` 清除监听。
    ///   - stream: 需要监听的远端流。
    /// - Throws: 房间不可用或帧监听设置失败时抛出错误。
    func setRemoteVideoFrameListener(
        _ listener: RtcRemoteVideoFrameListener?, for stream: RemoteStream
    ) throws {
        try operationLock.withLock {
            guard let context = stateLock.withLock({ activeRoom }), context.roomID == stream.roomID
            else {
                if listener == nil { return }
                throw XmaxError(code: .rtcError, message: "Remote stream is unavailable")
            }

            let id = context.id
            let guardedListener: RtcRemoteVideoFrameListener?
            if let listener {
                guardedListener = { [weak self] frame in
                    guard let self, self.stateLock.withLock({ self.activeRoom?.id == id }) else {
                        return
                    }
                    listener(frame)
                }
            } else {
                guardedListener = nil
            }
            try context.room.setRemoteVideoFrameListener(guardedListener, for: stream.userID)
        }
    }

    /// 向当前 RTC 房间发送消息。
    ///
    /// - Parameters:
    ///   - message: 完整 JSON 信令。
    ///   - reportFailure: 异步发送失败时是否上报房间故障。
    ///   - replacingPendingMessage: 合并键；同键且尚未发送的信令仅保留最新内容。
    /// - Returns: 本条信令的发送任务，可用于等待独立的发送结果。
    /// - Throws: 入队失败时抛出错误。
    @discardableResult
    func sendRoomMessage(
        _ message: String,
        reportFailure: Bool = true,
        replacingPendingMessage key: String? = nil
    ) throws -> Task<Void, any Error> {
        try withRoom {
            try $0.sendRoomMessage(message, reportFailure: reportFailure, replacingPendingMessage: key)
        }
    }

    /// 丢弃当前房间尚未开始发送的可合并信令。
    ///
    /// - Parameter key: 需要清理的合并键；`nil` 清理所有可合并信令。
    func discardPendingMessages(key: String?) {
        operationLock.withLock {
            let room = stateLock.withLock { activeRoom?.room }
            room?.discardPendingMessages(key: key)
        }
    }

    /// 等待已入队的房间信令发送完成。
    ///
    /// - Throws: 房间不可用、消息发送失败或等待取消时抛出错误。
    func awaitPendingMessages() async throws {
        let room = try operationLock.withLock { try requireRoom().room }
        try await room.awaitPendingMessages()
    }

    /// 设置 RTC 连接及媒体事件监听器。
    ///
    /// - Parameter listener: 事件监听器；传入 `nil` 清除监听。
    func setEventListener(_ listener: (any RtcEventListener)?) {
        stateLock.withLock { eventListener = listener }
    }

    /// 设置 RTC 网络及媒体质量监听器。
    ///
    /// - Parameter listener: 质量监听器；传入 `nil` 清除监听。
    func setQualityListener(_ listener: (any RtcQualityListener)?) {
        stateLock.withLock { qualityListener = listener }
    }
}

private extension RtcManager {
    /// 保存一次共享初始化任务及仍在等待的调用者。
    struct Initialization {

        /// 初始化标识
        let id: UUID

        /// 共享任务与等待者
        let task: Task<RtcEngineLease, any Error>
        var waiterIDs: Set<UUID>
    }

    /// 关联一次连接的身份与平台房间，隔离旧连接的迟到事件。
    final class RoomContext: Sendable {

        /// 连接标识
        let id: UUID
        let roomID: String

        /// 平台房间
        let room: any RtcRoom

        /// 关联一次连接的身份和平台房间。
        ///
        /// - Parameters:
        ///   - id: 当前连接的唯一标识。
        ///   - roomID: 服务端 RTC 房间标识。
        ///   - room: 本次连接使用的平台房间。
        init(id: UUID, roomID: String, room: any RtcRoom) {
            self.id = id
            self.roomID = roomID
            self.room = room
        }
    }

    /// 保存待完成进房操作的房间、恢复点和超时任务。
    final class PendingJoin: @unchecked Sendable {

        /// 房间上下文
        let context: RoomContext

        /// 完成通知与超时
        let continuation: CheckedContinuation<Void, any Error>
        var timeoutTask: Task<Void, Never>?

        /// 创建等待进房完成的上下文。
        ///
        /// - Parameters:
        ///   - context: 待连接的房间上下文。
        ///   - continuation: 用于恢复进房调用的 continuation。
        init(context: RoomContext, continuation: CheckedContinuation<Void, any Error>) {
            self.context = context
            self.continuation = continuation
        }
    }

    /// 接管仍有效的引擎租约；初始化已失效时释放租约。
    ///
    /// - Parameters:
    ///   - initializationID: 当前初始化操作标识。
    ///   - lease: 新获取的引擎租约。
    /// - Throws: 初始化已被取消或替换时抛出取消错误。
    func finishInitialization(initializationID: UUID, lease: RtcEngineLease)
        async throws
    {
        let installed = operationLock.withLock {
            stateLock.withLock { () -> Bool in
                if engineLease?.id == lease.id { return true }
                guard initialization?.id == initializationID else { return false }
                engineLease = lease
                initialization = nil
                return true
            }
        }
        if !installed {
            await engineManager.release(lease)
            throw Self.cancelledError(operation: "RTC initialization")
        }
    }

    /// 移除初始化等待者，并在无等待者时取消租约获取。
    ///
    /// - Parameters:
    ///   - initializationID: 初始化操作标识。
    ///   - waiterID: 需要取消的等待者标识。
    func cancelInitializationWaiter(initializationID: UUID, waiterID: UUID) {
        let task = stateLock.withLock { () -> Task<RtcEngineLease, any Error>? in
            guard var initialization,
                initialization.id == initializationID,
                initialization.waiterIDs.remove(waiterID) != nil
            else {
                return nil
            }
            guard initialization.waiterIDs.isEmpty else {
                self.initialization = initialization
                return nil
            }
            self.initialization = nil
            return initialization.task
        }
        task?.cancel()
    }

    /// 清除匹配的初始化操作。
    ///
    /// - Parameter id: 需要清除的初始化标识。
    func clearInitialization(id: UUID) {
        stateLock.withLock {
            if initialization?.id == id {
                initialization = nil
            }
        }
    }

    /// 创建房间并启动进房及超时等待。
    ///
    /// - Parameters:
    ///   - id: 本次连接的唯一标识。
    ///   - configuration: 房间及用户连接配置。
    ///   - continuation: 进房完成或失败时恢复的 continuation。
    func beginJoin(
        id: UUID, configuration: RoomJoinConfiguration,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        operationLock.withLock {
            do {
                try Task.checkCancellation()
                let engine = try requireEngine()
                guard stateLock.withLock({ activeRoom == nil && pendingJoin == nil }) else {
                    throw XmaxError(code: .rtcError, message: "RTC room is already active")
                }

                let room = try engine.createRoom(roomID: configuration.roomID)
                let context = RoomContext(id: id, roomID: configuration.roomID, room: room)
                let pending = PendingJoin(context: context, continuation: continuation)
                stateLock.withLock { pendingJoin = pending }
                room.setEventListener { [weak self] event in
                    self?.handleRoomEvent(event, id: id)
                }

                pending.timeoutTask = Task { [weak self, joinTimeout] in
                    try? await Task.sleep(nanoseconds: joinTimeout)
                    guard !Task.isCancelled else { return }
                    self?.failPendingJoin(
                        id: id, error: XmaxError(code: .timeout, message: "RTC join room timed out")
                    )
                }
                try room.join(configuration: configuration)
            } catch {
                if stateLock.withLock({ pendingJoin?.context.id == id }) {
                    failPendingJoin(id: id, error: XmaxError.from(error))
                } else {
                    continuation.resume(throwing: XmaxError.from(error))
                }
            }
        }
    }

    /// 处理当前连接的房间事件，忽略已失效连接的事件。
    ///
    /// - Parameters:
    ///   - event: 平台房间事件。
    ///   - id: 产生事件的连接标识。
    func handleRoomEvent(_ event: RtcRoomEvent, id: UUID) {
        operationLock.withLock {
            guard
                let context = stateLock.withLock({
                    activeRoom?.id == id ? activeRoom : pendingJoin?.context
                }),
                context.id == id
            else { return }

            switch event {
            case .joined:
                finishJoin(context)
            case .publication(let userID, let published):
                notifyPublication(id: id, userID: userID, published: published)
            case .failure(let error):
                failRoom(id: id, error: error)
            case .quality(let uplink, let downlink):
                notifyQuality(id: id) { $0.onNetworkQuality(uplink: uplink, downlink: downlink) }
            case .uplinkVideoStatistics(let statistics):
                notifyQuality(id: id) { $0.onUplinkVideoStatistics(statistics) }
            case .downlinkVideoStatistics(let statistics):
                notifyQuality(id: id) { $0.onDownlinkVideoStatistics(statistics) }
            case .performance(let limited, let width, let height, let fps):
                notifyQuality(id: id) {
                    $0.onPerformanceAlarm(
                        limited: limited,
                        suggestedWidth: width,
                        suggestedHeight: height,
                        suggestedFrameRate: fps
                    )
                }
            }
        }
    }

    /// 将待连接房间转为活动房间并恢复进房调用。
    ///
    /// - Parameter context: 成功连接的房间上下文。
    func finishJoin(_ context: RoomContext) {
        guard let pending = stateLock.withLock({ pendingJoin }), pending.context === context else {
            return
        }
        stateLock.withLock {
            activeRoom = context
            pendingJoin = nil
        }
        pending.timeoutTask?.cancel()
        pending.continuation.resume()
    }

    /// 结束匹配的进房等待并释放未连接成功的房间。
    ///
    /// - Parameters:
    ///   - id: 待结束的连接标识。
    ///   - error: 返回给进房调用者的错误。
    func failPendingJoin(id: UUID, error: any Error) {
        operationLock.withLock {
            let pending = stateLock.withLock { () -> PendingJoin? in
                guard pendingJoin?.context.id == id else { return nil }
                let value = pendingJoin
                pendingJoin = nil
                return value
            }
            guard let pending else { return }
            pending.timeoutTask?.cancel()
            tearDownRoom(pending.context)
            pending.continuation.resume(throwing: error)
        }
    }

    /// 将连接失败返回给进房调用者或当前连接监听器。
    ///
    /// - Parameters:
    ///   - id: 失败连接的标识。
    ///   - error: 连接失败原因。
    func failRoom(id: UUID, error: XmaxError) {
        if stateLock.withLock({ pendingJoin?.context.id == id }) {
            failPendingJoin(id: id, error: error)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let listener = stateLock.withLock { activeRoom?.id == id ? eventListener : nil }
            listener?.onRtcFailure(error)
        }
    }

    /// 在主线程通知仍有效连接的视频发布变化。
    ///
    /// - Parameters:
    ///   - id: 连接标识。
    ///   - userID: 远端用户标识。
    ///   - published: 远端视频是否已发布。
    func notifyPublication(id: UUID, userID: String, published: Bool) {
        guard stateLock.withLock({ activeRoom?.id == id }) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let listener = stateLock.withLock { activeRoom?.id == id ? eventListener : nil }
            listener?.onRemoteVideoPublished(userID: userID, published: published)
        }
    }

    /// 在主线程向当前连接的监听器转发质量事件。
    ///
    /// - Parameters:
    ///   - id: 连接标识。
    ///   - action: 需要在质量监听器上执行的通知。
    func notifyQuality(
        id: UUID, _ action: @escaping @MainActor @Sendable (any RtcQualityListener) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let listener = stateLock.withLock { activeRoom?.id == id ? qualityListener : nil }
            if let listener { action(listener) }
        }
    }

    /// 解除房间事件监听并销毁房间。
    ///
    /// - Parameter context: 需要释放的房间上下文；`nil` 时不执行操作。
    func tearDownRoom(_ context: RoomContext?) {
        context?.room.setEventListener(nil)
        context?.room.destroy()
    }

    /// 获取当前有效租约持有的 RTC 引擎。
    ///
    /// - Returns: 当前 RTC 平台引擎。
    /// - Throws: 引擎未初始化时抛出错误。
    func requireEngine() throws -> any RtcPlatform {
        guard let engine = stateLock.withLock({ engineLease?.engine }) else {
            throw XmaxError(code: .rtcError, message: "RTC engine is not initialized")
        }
        return engine
    }

    /// 获取当前已连接的房间上下文。
    ///
    /// - Returns: 活动房间上下文。
    /// - Throws: 尚未加入房间时抛出错误。
    func requireRoom() throws -> RoomContext {
        guard let context = stateLock.withLock({ activeRoom }) else {
            throw XmaxError(code: .rtcError, message: "RTC room is not joined")
        }
        return context
    }

    /// 在操作锁保护下使用当前 RTC 引擎。
    ///
    /// - Parameter operation: 使用引擎执行的同步操作。
    /// - Returns: 操作的返回值。
    /// - Throws: 引擎不可用或操作失败时抛出错误。
    func withEngine<T>(_ operation: (any RtcPlatform) throws -> T) throws -> T {
        try operationLock.withLock { try operation(requireEngine()) }
    }

    /// 在引擎存在时同步执行操作。
    ///
    /// - Parameter operation: 使用引擎执行的操作；无引擎时跳过。
    /// - Throws: 引擎操作失败时抛出错误。
    func withOptionalEngine(_ operation: (any RtcPlatform) throws -> Void) throws {
        try operationLock.withLock {
            if let engine = stateLock.withLock({ engineLease?.engine }) { try operation(engine) }
        }
    }

    /// 在操作锁保护下使用当前 RTC 房间。
    ///
    /// - Parameter operation: 使用房间执行的同步操作。
    /// - Returns: 操作的返回值。
    /// - Throws: 房间不可用或操作失败时抛出错误。
    func withRoom<T>(_ operation: (any RtcRoom) throws -> T) throws -> T {
        try operationLock.withLock { try operation(requireRoom().room) }
    }

    /// 在活动房间存在时同步执行操作。
    ///
    /// - Parameter operation: 使用房间执行的操作；无房间时跳过。
    /// - Throws: 房间操作失败时抛出错误。
    func withOptionalRoom(_ operation: (any RtcRoom) throws -> Void) throws {
        try operationLock.withLock {
            if let context = stateLock.withLock({ activeRoom }) { try operation(context.room) }
        }
    }

    /// 构造 RTC 操作取消错误。
    ///
    /// - Parameter operation: 被取消操作的名称。
    /// - Returns: 包含操作名称的取消错误。
    static func cancelledError(operation: String) -> XmaxError {
        XmaxError(code: .cancelled, message: "\(operation) was cancelled")
    }
}
