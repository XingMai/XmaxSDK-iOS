//
//  RtcManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 管理 RTC 租约、连接等待、取消及事件有效期。
final class RtcManager: RtcManaging, @unchecked Sendable {

    // RTC 配置
    static let joinTimeoutNanoseconds: UInt64 = 15000000000

    // 依赖
    private let engineManager: RtcEngineManager
    private let joinTimeout: UInt64

    // 并发控制
    private let stateLock = NSLock()
    private let operationLock = NSRecursiveLock()

    // RTC 资源
    private var engineLease: RtcEngineLease?
    private var activeRoom: RoomContext?
    private var pendingJoin: PendingJoin?

    // 事件监听
    private weak var eventListener: (any RtcEventListener)?
    private weak var qualityListener: (any RtcQualityListener)?

    // 运行状态
    private var initialization: Initialization?

    init(
        engineManager: RtcEngineManager = .shared,
        joinTimeoutNanoseconds: UInt64 = RtcManager.joinTimeoutNanoseconds
    ) {
        self.engineManager = engineManager
        joinTimeout = joinTimeoutNanoseconds
    }

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

    func configureVideoEncoding(_ configuration: VideoEncodingConfiguration) throws {
        guard configuration.width > 0, configuration.height > 0, configuration.frameRate > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video width, height, and frame rate must be positive")
        }
        try withEngine { try $0.configureVideoEncoding(configuration) }
    }

    func useExternalVideoSource() throws {
        try withEngine { try $0.useExternalVideoSource() }
    }

    func configureLocalVideoMirror(for position: CameraPosition) throws {
        try withOptionalEngine { try $0.configureLocalVideoMirror(for: position) }
    }

    func startAudioCapture() throws {
        try withEngine { try $0.startAudioCapture() }
    }

    func stopAudioCapture() throws {
        try withOptionalEngine { try $0.stopAudioCapture() }
    }

    func startExternalAudioSource() throws {
        try withEngine { try $0.startExternalAudioSource() }
    }

    func stopExternalAudioSource() throws {
        try withOptionalEngine { try $0.stopExternalAudioSource() }
    }

    func pushExternalVideoFrame(_ frame: VideoFrame) throws {
        try withEngine { try $0.pushExternalVideoFrame(frame) }
    }

    func pushExternalAudioFrame(_ frame: AudioFrame) throws {
        try withEngine { try $0.pushExternalAudioFrame(frame) }
    }

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

    func publishLocalVideo() throws {
        try withRoom { try $0.publishLocalVideo(true) }
    }

    func unpublishLocalVideo() throws {
        try withOptionalRoom { try $0.publishLocalVideo(false) }
    }

    func publishLocalAudio() throws {
        try withRoom { try $0.publishLocalAudio(true) }
    }

    func unpublishLocalAudio() throws {
        try withOptionalRoom { try $0.publishLocalAudio(false) }
    }

    func subscribeRemoteVideo(userID: String, subscribe: Bool) throws {
        try withRoom { try $0.subscribeRemoteVideo(userID: userID, subscribe: subscribe) }
    }

    func subscribeRemoteAudio(userID: String, subscribe: Bool) throws {
        try withRoom { try $0.subscribeRemoteAudio(userID: userID, subscribe: subscribe) }
    }

    func setRemoteAudioVolume(_ volume: Int, for userID: String) throws {
        guard (0...100).contains(volume) else {
            throw XmaxError(
                code: .invalidConfiguration, message: "RTC audio volume must be between 0 and 100")
        }
        try withRoom { try $0.setRemoteAudioVolume(volume, for: userID) }
    }

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

    @discardableResult
    func sendRoomMessage(_ message: String, reportFailure: Bool = true) throws -> Task<Void, any Error> {
        try withRoom { try $0.sendRoomMessage(message, reportFailure: reportFailure) }
    }

    func awaitPendingMessages() async throws {
        let room = try operationLock.withLock { try requireRoom().room }
        try await room.awaitPendingMessages()
    }

    func setEventListener(_ listener: (any RtcEventListener)?) {
        stateLock.withLock { eventListener = listener }
    }

    func setQualityListener(_ listener: (any RtcQualityListener)?) {
        stateLock.withLock { qualityListener = listener }
    }
}

private extension RtcManager {
    struct Initialization {
        let id: UUID
        let task: Task<RtcEngineLease, any Error>
        var waiterIDs: Set<UUID>
    }

    /// 关联一次连接的身份与平台房间，隔离旧连接的迟到事件。
    final class RoomContext: Sendable {
        let id: UUID
        let roomID: String
        let room: any RtcRoom

        init(id: UUID, roomID: String, room: any RtcRoom) {
            self.id = id
            self.roomID = roomID
            self.room = room
        }
    }

    final class PendingJoin: @unchecked Sendable {
        let context: RoomContext
        let continuation: CheckedContinuation<Void, any Error>
        var timeoutTask: Task<Void, Never>?

        init(context: RoomContext, continuation: CheckedContinuation<Void, any Error>) {
            self.context = context
            self.continuation = continuation
        }
    }

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

    func clearInitialization(id: UUID) {
        stateLock.withLock {
            if initialization?.id == id {
                initialization = nil
            }
        }
    }

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

    func notifyPublication(id: UUID, userID: String, published: Bool) {
        guard stateLock.withLock({ activeRoom?.id == id }) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let listener = stateLock.withLock { activeRoom?.id == id ? eventListener : nil }
            listener?.onRemoteVideoPublished(userID: userID, published: published)
        }
    }

    func notifyQuality(
        id: UUID, _ action: @escaping @MainActor @Sendable (any RtcQualityListener) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let listener = stateLock.withLock { activeRoom?.id == id ? qualityListener : nil }
            if let listener { action(listener) }
        }
    }

    func tearDownRoom(_ context: RoomContext?) {
        context?.room.setEventListener(nil)
        context?.room.destroy()
    }

    func requireEngine() throws -> any RtcPlatform {
        guard let engine = stateLock.withLock({ engineLease?.engine }) else {
            throw XmaxError(code: .rtcError, message: "RTC engine is not initialized")
        }
        return engine
    }

    func requireRoom() throws -> RoomContext {
        guard let context = stateLock.withLock({ activeRoom }) else {
            throw XmaxError(code: .rtcError, message: "RTC room is not joined")
        }
        return context
    }

    func withEngine<T>(_ operation: (any RtcPlatform) throws -> T) throws -> T {
        try operationLock.withLock { try operation(requireEngine()) }
    }

    func withOptionalEngine(_ operation: (any RtcPlatform) throws -> Void) throws {
        try operationLock.withLock {
            if let engine = stateLock.withLock({ engineLease?.engine }) { try operation(engine) }
        }
    }

    func withRoom<T>(_ operation: (any RtcRoom) throws -> T) throws -> T {
        try operationLock.withLock { try operation(requireRoom().room) }
    }

    func withOptionalRoom(_ operation: (any RtcRoom) throws -> Void) throws {
        try operationLock.withLock {
            if let context = stateLock.withLock({ activeRoom }) { try operation(context.room) }
        }
    }

    static func cancelledError(operation: String) -> XmaxError {
        XmaxError(code: .cancelled, message: "\(operation) was cancelled")
    }
}
