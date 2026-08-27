import Foundation
import UIKit
@preconcurrency import VolcEngineRTC

/// 提供基于火山引擎的 RTC 基础能力。
final class RtcManager: RtcManaging, @unchecked Sendable {

    // RTC 配置
    /// RTC 进房回调的最长等待时间。
    static let joinTimeoutNanoseconds: UInt64 = 15_000_000_000

    // 依赖
    private let engineManager: RtcEngineManager

    // 并发控制
    private let stateLock = NSLock()
    private let operationLock = NSRecursiveLock()

    // RTC 资源
    private var remoteStreamIDs: [RemoteStream: String] = [:]
    private var engineLease: RtcEngineLease?
    private var engineBridge: RtcEngineEventBridge?
    private var activeRoom: RoomContext?
    private var pendingJoin: PendingJoin?
    private let videoFrameCache = RtcVideoFrameCache()

    // 事件监听
    private weak var eventListener: (any RtcEventListener)?
    private weak var qualityListener: (any RtcQualityListener)?
    private var cameraPreviewReadyListener: RtcCameraPreviewReadyListener?

    // 运行状态
    private var initialization: Initialization?
    private var localVideoMirrorType = ByteRTCMirrorType.none
    private var isCameraVideoSourceActive = false
    private var hasCapturedFirstLocalVideoFrame = false
    private var hasBoundLocalVideoCanvas = false
    private var hasReportedCameraPreviewReady = false

    init(engineManager: RtcEngineManager = .shared) {
        self.engineManager = engineManager
    }

    func initialize() async throws {
        let initialization = stateLock.withLock { () -> Initialization? in
            guard engineLease == nil else {
                return nil
            }
            if let initialization {
                return initialization
            }

            let initialization = Initialization(
                id: UUID(),
                task: Task {
                    try await engineManager.acquire()
                }
            )
            self.initialization = initialization
            return initialization
        }
        guard let initialization else {
            return
        }

        do {
            let lease = try await initialization.task.value
            try finishInitialization(
                initializationID: initialization.id,
                lease: lease
            )
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
            stateLock.withLock { () -> EngineResources in
                let resources = EngineResources(
                    lease: engineLease,
                    initialization: initialization
                )
                engineLease?.engine.delegate = nil
                engineLease = nil
                engineBridge = nil
                initialization = nil
                cameraPreviewReadyListener = nil
                remoteStreamIDs.removeAll()
                videoFrameCache.removeAll()
                isCameraVideoSourceActive = false
                hasCapturedFirstLocalVideoFrame = false
                hasBoundLocalVideoCanvas = false
                hasReportedCameraPreviewReady = false
                return resources
            }
        }

        resources.initialization?.task.cancel()
        if let lease = resources.lease {
            await engineManager.release(lease)
        }
    }

    func configureVideoEncoding(
        _ configuration: VideoEncodingConfiguration
    ) throws {
        try validateVideoDimensions(
            width: configuration.width,
            height: configuration.height,
            frameRate: configuration.frameRate
        )
        try withEngine { engine in
            try checkResult(
                engine.setVideoEncoderConfig(
                    RtcVideoConverter.makeEncoderConfiguration(configuration)
                ),
                operation: "setVideoEncoderConfig"
            )
        }
    }

    func startVideoCapture(
        width: Int,
        height: Int,
        frameRate: Int
    ) throws {
        try validateVideoDimensions(
            width: width,
            height: height,
            frameRate: frameRate
        )
        resetCameraPreviewReadiness(cameraSourceActive: false)
        do {
            try withEngine { engine in
                try checkResult(
                    engine.setVideoSourceType(.internal),
                    operation: "setVideoSourceType"
                )

                let configuration = ByteRTCVideoCaptureConfig()
                configuration.preference = .mannal
                configuration.videoSize = CGSize(width: width, height: height)
                configuration.frameRate = frameRate
                try checkResult(
                    engine.setVideoCaptureConfig(configuration),
                    operation: "setVideoCaptureConfig"
                )
                resetCameraPreviewReadiness(cameraSourceActive: true)
                try checkResult(
                    engine.startVideoCapture(),
                    operation: "startVideoCapture"
                )
            }
        } catch {
            resetCameraPreviewReadiness(cameraSourceActive: false)
            throw error
        }
    }

    func stopVideoCapture() throws {
        defer {
            resetCameraPreviewReadiness(cameraSourceActive: false)
        }
        try withOptionalEngine { engine in
            try checkResult(
                engine.stopVideoCapture(),
                operation: "stopVideoCapture"
            )
        }
    }

    func switchCamera(to position: CameraPosition) throws {
        try withEngine { engine in
            try checkResult(
                engine.switchCamera(RtcVideoConverter.convertCameraID(position)),
                operation: "switchCamera"
            )
            let mirrorType = RtcVideoConverter.convertMirrorType(position)
            try checkResult(
                engine.setLocalVideoMirrorType(mirrorType),
                operation: "setLocalVideoMirrorType"
            )
            stateLock.withLock {
                localVideoMirrorType = mirrorType
            }
        }
    }

    func useExternalVideoSource() throws {
        resetCameraPreviewReadiness(cameraSourceActive: false)
        try withEngine { engine in
            videoFrameCache.removeAll()
            try checkResult(
                engine.setVideoSourceType(.external),
                operation: "setVideoSourceType"
            )
            try checkResult(
                engine.setLocalVideoMirrorType(.none),
                operation: "setLocalVideoMirrorType"
            )
            stateLock.withLock {
                localVideoMirrorType = .none
            }
        }
    }

    func startExternalAudioSource() throws {
        try withEngine { engine in
            try checkResult(
                engine.setAudioSourceType(.external),
                operation: "setAudioSourceType"
            )
            try checkResult(
                engine.startAudioCapture(),
                operation: "startAudioCapture"
            )
        }
    }

    func stopExternalAudioSource() throws {
        try withOptionalEngine { engine in
            try checkResult(
                engine.stopAudioCapture(),
                operation: "stopAudioCapture"
            )
        }
    }

    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws {
        let mirrorType = RtcVideoConverter.convertMirrorType(position)
        stateLock.withLock {
            localVideoMirrorType = mirrorType
        }
        try withOptionalEngine { engine in
            try checkResult(
                engine.setLocalVideoMirrorType(mirrorType),
                operation: "setLocalVideoMirrorType"
            )
        }
    }

    func pushExternalVideoFrame(
        _ frame: VideoFrame,
        seiData: Data?
    ) throws {
        try withEngine { engine in
            let rtcFrame = try videoFrameCache.frame(
                for: frame,
                seiData: seiData
            )
            _ = engine.pushExternalVideoFrame(rtcFrame.value)
        }
    }

    func pushExternalAudioFrame(_ frame: AudioFrame) throws {
        let rtcFrame = try RtcAudioConverter.convertFrame(frame)
        try withEngine { engine in
            _ = engine.pushExternalAudioFrame(rtcFrame)
        }
    }

    func joinRoom(
        configuration: RoomJoinConfiguration
    ) async throws {
        try validateJoinConfiguration(configuration)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                beginJoin(
                    configuration: configuration,
                    continuation: continuation
                )
            }
        } onCancel: {
            cancelPendingJoin(
                error: Self.cancelledError(operation: "RTC join room")
            )
        }
    }

    func leaveRoom() async {
        operationLock.withLock {
            let resources = stateLock.withLock { () -> RoomResources in
                let resources = RoomResources(
                    activeRoom: activeRoom,
                    pendingJoin: pendingJoin
                )
                activeRoom = nil
                pendingJoin = nil
                remoteStreamIDs.removeAll()
                return resources
            }
            resources.pendingJoin?.timeoutTask?.cancel()
            resources.pendingJoin?.continuation.resume(
                throwing: Self.cancelledError(operation: "RTC join room")
            )
            tearDownRoom(resources.pendingJoin?.context.room, leave: false)
            tearDownRoom(resources.activeRoom?.room, leave: true)
        }
    }

    func publishLocalVideo() throws {
        try operationLock.withLock {
            let resources = try requireRoomResources()
            let mirrorType = stateLock.withLock { localVideoMirrorType }
            try checkResult(
                resources.engine.setLocalVideoMirrorType(mirrorType),
                operation: "setLocalVideoMirrorType"
            )
            try checkResult(
                resources.room.publishStreamVideo(true),
                operation: "publishStreamVideo"
            )
        }
    }

    func unpublishLocalVideo() throws {
        try withOptionalRoom { room in
            try checkResult(
                room.publishStreamVideo(false),
                operation: "publishStreamVideo"
            )
        }
    }

    func publishLocalAudio() throws {
        try withRoom { room in
            try checkResult(
                room.publishStreamAudio(true),
                operation: "publishStreamAudio"
            )
        }
    }

    func unpublishLocalAudio() throws {
        try withOptionalRoom { room in
            try checkResult(
                room.publishStreamAudio(false),
                operation: "publishStreamAudio"
            )
        }
    }

    func subscribeRemoteVideo(
        userID: String,
        subscribe: Bool
    ) throws {
        let normalizedUserID = userID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedUserID.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "RTC user ID cannot be empty"
            )
        }

        try operationLock.withLock {
            let room = try requireRoom()
            let streamID = stateLock.withLock {
                remoteStreamIDs.first { stream, _ in
                    stream.userID == normalizedUserID
                }?.value ?? normalizedUserID
            }
            try checkResult(
                room.subscribeStreamVideo(streamID, subscribe: subscribe),
                operation: "subscribeStreamVideo"
            )
        }
    }

    func subscribeRemoteAudio(
        userID: String,
        subscribe: Bool
    ) throws {
        let normalizedUserID = userID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedUserID.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "RTC user ID cannot be empty"
            )
        }

        try operationLock.withLock {
            let room = try requireRoom()
            let streamID = stateLock.withLock {
                remoteStreamIDs.first { stream, _ in
                    stream.userID == normalizedUserID
                }?.value ?? normalizedUserID
            }
            try checkResult(
                room.subscribeStreamAudio(streamID, subscribe: subscribe),
                operation: "subscribeStreamAudio"
            )
        }
    }

    @MainActor
    func bindLocalVideo(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        try operationLock.withLock {
            let engine = try requireEngine()
            let canvas = RtcVideoConverter.makeCanvas(
                view: view,
                contentMode: contentMode
            )
            try checkResult(
                engine.setLocalVideoCanvas(withCanvas: canvas),
                operation: "setLocalVideoCanvas"
            )
            let mirrorType = stateLock.withLock { localVideoMirrorType }
            try checkResult(
                engine.setLocalVideoMirrorType(mirrorType),
                operation: "setLocalVideoMirrorType"
            )
        }
        markLocalVideoCanvasBound()
    }

    @MainActor
    func unbindLocalVideo() throws {
        defer {
            markLocalVideoCanvasUnbound()
        }
        try withOptionalEngine { engine in
            try checkResult(
                engine.setLocalVideoCanvas(withCanvas: nil),
                operation: "setLocalVideoCanvas"
            )
        }
    }

    @MainActor
    func bindRemoteVideo(
        _ stream: RemoteStream,
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        try operationLock.withLock {
            let engine = try requireEngine()
            guard let streamID = stateLock.withLock({
                remoteStreamIDs[stream]
            }) else {
                throw XmaxError(
                    code: .rtcError,
                    message: "Remote stream is unavailable"
                )
            }
            let canvas = RtcVideoConverter.makeCanvas(
                view: view,
                contentMode: contentMode
            )
            try checkResult(
                engine.setRemoteVideoCanvas(streamID, withCanvas: canvas),
                operation: "setRemoteVideoCanvas"
            )
        }
    }

    @MainActor
    func unbindRemoteVideo(_ stream: RemoteStream) throws {
        try operationLock.withLock {
            guard let engine = stateLock.withLock({ engineLease?.engine }),
                  let streamID = stateLock.withLock({ remoteStreamIDs[stream] }) else {
                return
            }
            try checkResult(
                engine.setRemoteVideoCanvas(streamID, withCanvas: nil),
                operation: "setRemoteVideoCanvas"
            )
        }
    }

    var renderLibraryName: String {
        "VolcEngineRTC"
    }

    func sendRoomMessage(_ message: String) throws {
        guard !message.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "RTC room message cannot be empty"
            )
        }
        try withRoom { room in
            try checkResult(
                room.sendMessage(message),
                operation: "sendRoomMessage"
            )
        }
    }

    func setEventListener(_ listener: (any RtcEventListener)?) {
        stateLock.withLock {
            eventListener = listener
        }
    }

    func setCameraPreviewReadyListener(
        _ listener: RtcCameraPreviewReadyListener?
    ) {
        stateLock.withLock {
            cameraPreviewReadyListener = listener
        }
    }

    func setQualityListener(_ listener: (any RtcQualityListener)?) {
        stateLock.withLock {
            qualityListener = listener
        }
    }
}

private extension RtcManager {

    /// 保存一次共享初始化任务。
    struct Initialization {
        let id: UUID
        let task: Task<RtcEngineLease, any Error>
    }

    /// 保存销毁 Engine 时需要在锁外处理的资源。
    struct EngineResources {
        let lease: RtcEngineLease?
        let initialization: Initialization?
    }

    /// 保存一个已创建 RTC 房间及其回调桥。
    final class RoomContext: @unchecked Sendable {
        let roomID: String
        let room: ByteRTCRoom
        let bridge: RtcRoomEventBridge

        init(
            roomID: String,
            room: ByteRTCRoom,
            bridge: RtcRoomEventBridge
        ) {
            self.roomID = roomID
            self.room = room
            self.bridge = bridge
        }
    }

    /// 保存等待进房结果的 continuation 和超时任务。
    final class PendingJoin: @unchecked Sendable {
        let id: UUID
        let context: RoomContext
        let continuation: CheckedContinuation<Void, any Error>
        var timeoutTask: Task<Void, Never>?

        init(
            id: UUID,
            context: RoomContext,
            continuation: CheckedContinuation<Void, any Error>
        ) {
            self.id = id
            self.context = context
            self.continuation = continuation
        }
    }

    /// 保存离开房间时需要处理的活动和等待中资源。
    struct RoomResources {
        let activeRoom: RoomContext?
        let pendingJoin: PendingJoin?
    }

    /// 保存需要同时使用的 Engine 和 Room。
    struct ActiveRoomResources {
        let engine: ByteRTCEngine
        let room: ByteRTCRoom
    }

    func finishInitialization(
        initializationID: UUID,
        lease: RtcEngineLease
    ) throws {
        operationLock.lock()
        let outcome = stateLock.withLock { () -> InitializationOutcome in
            if engineLease?.id == lease.id {
                return .alreadyInstalled
            }
            guard initialization?.id == initializationID else {
                return .cancelled
            }

            let bridge = makeEngineBridge()
            lease.engine.delegate = bridge
            engineLease = lease
            engineBridge = bridge
            initialization = nil
            return .installed
        }
        operationLock.unlock()

        if outcome == .cancelled {
            Task {
                await engineManager.release(lease)
            }
            throw Self.cancelledError(operation: "RTC initialization")
        }
    }

    func clearInitialization(id: UUID) {
        stateLock.withLock {
            if initialization?.id == id {
                initialization = nil
            }
        }
    }

    func makeEngineBridge() -> RtcEngineEventBridge {
        RtcEngineEventBridge(
            onFirstLocalVideoFrame: { [weak self] engine in
                self?.handleFirstLocalVideoFrame(engine: engine)
            },
            onSei: { [weak self] engine, streamID, info, message in
                self?.handleSei(
                    engine: engine,
                    streamID: streamID,
                    info: info,
                    message: message
                )
            },
            onSystemStats: { [weak self] engine, stats in
                self?.handleSystemStats(engine: engine, stats: stats)
            },
            onPerformanceAlarm: { [weak self] engine, info, reason, data in
                self?.handlePerformanceAlarm(
                    engine: engine,
                    roomID: info.roomId,
                    reason: reason,
                    data: data
                )
            }
        )
    }

    func makeRoomBridge() -> RtcRoomEventBridge {
        RtcRoomEventBridge(
            onRoomState: { [weak self] room, roomID, _, state, _ in
                self?.handleRoomState(room: room, roomID: roomID, state: state)
            },
            onRemoteVideo: { [weak self] room, streamID, info, published in
                self?.handleRemoteVideo(
                    room: room,
                    streamID: streamID,
                    info: info,
                    published: published
                )
            },
            onNetworkQuality: { [weak self] room, local, remote in
                self?.handleNetworkQuality(
                    room: room,
                    local: local,
                    remote: remote
                )
            },
            onLocalStats: { [weak self] room, stats in
                self?.handleLocalStats(room: room, stats: stats)
            },
            onRemoteStats: { [weak self] room, stats in
                self?.handleRemoteStats(room: room, stats: stats)
            }
        )
    }

    func beginJoin(
        configuration: RoomJoinConfiguration,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        operationLock.lock()
        defer { operationLock.unlock() }

        if Task.isCancelled {
            continuation.resume(
                throwing: Self.cancelledError(operation: "RTC join room")
            )
            return
        }

        let engine: ByteRTCEngine
        do {
            engine = try requireEngine()
        } catch {
            continuation.resume(throwing: error)
            return
        }

        let canJoin = stateLock.withLock {
            activeRoom == nil && pendingJoin == nil
        }
        guard canJoin else {
            continuation.resume(
                throwing: XmaxError(
                    code: .rtcError,
                    message: "RTC room is already active"
                )
            )
            return
        }
        guard let room = engine.createRTCRoom(configuration.roomID) else {
            continuation.resume(
                throwing: XmaxError(
                    code: .rtcError,
                    message: "Failed to create RTC room"
                )
            )
            return
        }

        let bridge = makeRoomBridge()
        let context = RoomContext(
            roomID: configuration.roomID,
            room: room,
            bridge: bridge
        )
        let pendingJoin = PendingJoin(
            id: UUID(),
            context: context,
            continuation: continuation
        )
        room.delegate = bridge
        stateLock.withLock {
            self.pendingJoin = pendingJoin
        }
        if Task.isCancelled {
            failPendingJoin(
                id: pendingJoin.id,
                error: Self.cancelledError(operation: "RTC join room")
            )
            return
        }
        pendingJoin.timeoutTask = Task { [weak self, weak pendingJoin] in
            try? await Task.sleep(nanoseconds: Self.joinTimeoutNanoseconds)
            guard !Task.isCancelled, let pendingJoin else {
                return
            }
            self?.failPendingJoin(
                id: pendingJoin.id,
                error: XmaxError(
                    code: .timeout,
                    message: "RTC join room timed out"
                )
            )
        }

        let userInfo = ByteRTCUserInfo()
        userInfo.userId = configuration.userID
        userInfo.extraInfo = ""
        let roomConfiguration = ByteRTCRoomConfig()
        roomConfiguration.profile = .communication
        roomConfiguration.streamId = configuration.userID
        roomConfiguration.isPublishVideo = false
        roomConfiguration.isPublishAudio = false
        roomConfiguration.isAutoSubscribeVideo = true
        roomConfiguration.isAutoSubscribeAudio = false

        let result = room.joinRoom(
            configuration.token,
            userInfo: userInfo,
            userVisibility: true,
            roomConfig: roomConfiguration
        )
        if result < 0 {
            failPendingJoin(
                id: pendingJoin.id,
                error: rtcError(operation: "joinRoom", result: result)
            )
        }
    }

    func handleRoomState(
        room: ByteRTCRoom,
        roomID: String,
        state: Int
    ) {
        let pending = stateLock.withLock { pendingJoin }
        guard let pending,
              pending.context.room === room,
              pending.context.roomID == roomID else {
            return
        }

        if state == 0 {
            succeedPendingJoin(id: pending.id)
        } else {
            failPendingJoin(
                id: pending.id,
                error: XmaxError(
                    code: .rtcError,
                    message: "RTC join room failed: \(state)"
                )
            )
        }
    }

    func succeedPendingJoin(id: UUID) {
        operationLock.lock()
        let pending = stateLock.withLock { () -> PendingJoin? in
            guard pendingJoin?.id == id else {
                return nil
            }
            let pending = pendingJoin
            activeRoom = pending?.context
            pendingJoin = nil
            return pending
        }
        pending?.timeoutTask?.cancel()
        pending?.continuation.resume()
        operationLock.unlock()
    }

    func failPendingJoin(id: UUID, error: any Error) {
        operationLock.lock()
        let pending = stateLock.withLock { () -> PendingJoin? in
            guard pendingJoin?.id == id else {
                return nil
            }
            let pending = pendingJoin
            pendingJoin = nil
            return pending
        }
        pending?.timeoutTask?.cancel()
        if let pending {
            tearDownRoom(pending.context.room, leave: false)
            pending.continuation.resume(throwing: error)
        }
        operationLock.unlock()
    }

    func cancelPendingJoin(error: any Error) {
        guard let id = stateLock.withLock({ pendingJoin?.id }) else {
            return
        }
        failPendingJoin(id: id, error: error)
    }

    func handleRemoteVideo(
        room: ByteRTCRoom,
        streamID: String,
        info: ByteRTCStreamInfo,
        published: Bool
    ) {
        let result = stateLock.withLock {
            () -> ((any RtcEventListener)?, RemoteStream)? in
            guard activeRoom?.room === room else {
                return nil
            }
            let stream = RemoteStream(
                roomID: activeRoom?.roomID ?? info.roomId,
                userID: info.userId
            )
            if published {
                remoteStreamIDs[stream] = streamID
            } else {
                remoteStreamIDs.removeValue(forKey: stream)
            }
            return (eventListener, stream)
        }
        guard let (listener, stream) = result else {
            return
        }
        Task { @MainActor in
            listener?.onRemoteVideoPublished(
                userID: stream.userID,
                published: published
            )
        }
    }

    func handleFirstLocalVideoFrame(engine: ByteRTCEngine) {
        guard stateLock.withLock({ engineLease?.engine === engine }) else {
            return
        }
        markFirstLocalVideoFrameCaptured()
    }

    func resetCameraPreviewReadiness(cameraSourceActive: Bool) {
        stateLock.withLock {
            isCameraVideoSourceActive = cameraSourceActive
            hasCapturedFirstLocalVideoFrame = false
            hasReportedCameraPreviewReady = false
        }
    }

    func markFirstLocalVideoFrameCaptured() {
        let shouldNotify = stateLock.withLock {
            hasCapturedFirstLocalVideoFrame = true
            return markCameraPreviewReadyReportedIfNeeded()
        }
        notifyCameraPreviewReady(ifNeeded: shouldNotify)
    }

    func markLocalVideoCanvasBound() {
        let shouldNotify = stateLock.withLock {
            hasBoundLocalVideoCanvas = true
            return markCameraPreviewReadyReportedIfNeeded()
        }
        notifyCameraPreviewReady(ifNeeded: shouldNotify)
    }

    func markLocalVideoCanvasUnbound() {
        stateLock.withLock {
            hasBoundLocalVideoCanvas = false
        }
    }

    func markCameraPreviewReadyReportedIfNeeded() -> Bool {
        guard isCameraVideoSourceActive,
              hasCapturedFirstLocalVideoFrame,
              hasBoundLocalVideoCanvas,
              !hasReportedCameraPreviewReady,
              cameraPreviewReadyListener != nil else {
            return false
        }
        hasReportedCameraPreviewReady = true
        return true
    }

    func notifyCameraPreviewReady(ifNeeded shouldNotify: Bool) {
        guard shouldNotify else { return }
        Task { @MainActor [weak self] in
            self?.deliverCameraPreviewReady()
        }
    }

    @MainActor
    func deliverCameraPreviewReady() {
        let listener = stateLock.withLock { cameraPreviewReadyListener }
        listener?()
    }

    func handleSei(
        engine: ByteRTCEngine,
        streamID: String,
        info: ByteRTCStreamInfo,
        message: Data
    ) {
        guard let decodedMessage = String(data: message, encoding: .utf8) else {
            XmaxLogger.warn(
                "收到无法解码的 RTC SEI 消息 (Failed to Decode Incoming RTC SEI Message)",
                category: "RTC"
            )
            return
        }

        let result = stateLock.withLock {
            () -> ((any RtcEventListener)?, RemoteStream)? in
            guard engineLease?.engine === engine,
                  let activeRoom,
                  activeRoom.roomID == info.roomId else {
                return nil
            }
            let stream = RemoteStream(
                roomID: activeRoom.roomID,
                userID: info.userId
            )
            remoteStreamIDs[stream] = streamID
            return (eventListener, stream)
        }
        guard let (listener, stream) = result else {
            return
        }
        Task { @MainActor in
            listener?.onSeiMessageReceived(
                stream: stream,
                message: decodedMessage
            )
        }
    }

    func handleSystemStats(
        engine: ByteRTCEngine,
        stats: ByteRTCSysStats
    ) {
        guard stateLock.withLock({ engineLease?.engine === engine }) else {
            return
        }
        RtcStatsLogger.logSystemStats(stats)
    }

    func handlePerformanceAlarm(
        engine: ByteRTCEngine,
        roomID: String,
        reason: ByteRTCPerformanceAlarmReason,
        data: ByteRTCSourceWantedData
    ) {
        let listener = stateLock.withLock {
            () -> (any RtcQualityListener)? in
            guard engineLease?.engine === engine,
                  activeRoom?.roomID == roomID else {
                return nil
            }
            return qualityListener
        }
        guard stateLock.withLock({
            engineLease?.engine === engine && activeRoom?.roomID == roomID
        }) else {
            return
        }
        RtcStatsLogger.logPerformanceAlarm(reason: reason, data: data)
        guard let limited = RtcQualityConverter.resolvePerformanceLimited(reason) else {
            return
        }
        let suggestedWidth = Int(data.width)
        let suggestedHeight = Int(data.height)
        let suggestedFrameRate = Int(data.frameRate)
        Task { @MainActor in
            listener?.onPerformanceAlarm(
                limited: limited,
                suggestedWidth: suggestedWidth,
                suggestedHeight: suggestedHeight,
                suggestedFrameRate: suggestedFrameRate
            )
        }
    }

    func handleNetworkQuality(
        room: ByteRTCRoom,
        local: ByteRTCNetworkQualityStats,
        remote: [ByteRTCNetworkQualityStats]
    ) {
        let state = stateLock.withLock {
            () -> (Bool, (any RtcQualityListener)?) in
            guard activeRoom?.room === room else {
                return (false, nil)
            }
            return (true, qualityListener)
        }
        guard state.0 else {
            return
        }
        let listener = state.1
        RtcStatsLogger.logNetworkQuality(
            localQuality: local,
            remoteQualities: remote
        )
        let uplink = RtcQualityConverter.convertLevel(local.txQuality)
        let downlink = RtcQualityConverter.resolveDownlinkLevel(remote)
        Task { @MainActor in
            listener?.onNetworkQuality(
                uplink: uplink,
                downlink: downlink
            )
        }
    }

    func handleLocalStats(
        room: ByteRTCRoom,
        stats: ByteRTCLocalStreamStats
    ) {
        guard stateLock.withLock({ activeRoom?.room === room }) else {
            return
        }
        RtcStatsLogger.logLocalStreamStats(stats)
    }

    func handleRemoteStats(
        room: ByteRTCRoom,
        stats: ByteRTCRemoteStreamStats
    ) {
        guard stateLock.withLock({ activeRoom?.room === room }) else {
            return
        }
        RtcStatsLogger.logRemoteStreamStats(stats)
    }

    func tearDownRoom(_ room: ByteRTCRoom?, leave: Bool) {
        guard let room else {
            return
        }
        room.delegate = nil
        if leave {
            _ = room.publishStreamVideo(false)
            _ = room.publishStreamAudio(false)
            _ = room.leave()
        }
        room.destroy()
    }

    func withEngine<T>(
        _ operation: (ByteRTCEngine) throws -> T
    ) throws -> T {
        try operationLock.withLock {
            try operation(try requireEngine())
        }
    }

    func withOptionalEngine<T>(
        _ operation: (ByteRTCEngine) throws -> T
    ) throws -> T? {
        try operationLock.withLock {
            guard let engine = stateLock.withLock({ engineLease?.engine }) else {
                return nil
            }
            return try operation(engine)
        }
    }

    func withRoom<T>(
        _ operation: (ByteRTCRoom) throws -> T
    ) throws -> T {
        try operationLock.withLock {
            try operation(try requireRoom())
        }
    }

    func withOptionalRoom<T>(
        _ operation: (ByteRTCRoom) throws -> T
    ) throws -> T? {
        try operationLock.withLock {
            guard let room = stateLock.withLock({ activeRoom?.room }) else {
                return nil
            }
            return try operation(room)
        }
    }

    func requireEngine() throws -> ByteRTCEngine {
        guard let engine = stateLock.withLock({ engineLease?.engine }) else {
            throw XmaxError(
                code: .rtcError,
                message: "RTC engine is not initialized"
            )
        }
        return engine
    }

    func requireRoom() throws -> ByteRTCRoom {
        guard let room = stateLock.withLock({ activeRoom?.room }) else {
            throw XmaxError(
                code: .rtcError,
                message: "RTC room is not joined"
            )
        }
        return room
    }

    func requireRoomResources() throws -> ActiveRoomResources {
        ActiveRoomResources(
            engine: try requireEngine(),
            room: try requireRoom()
        )
    }

    func checkResult<T: BinaryInteger>(
        _ result: T,
        operation: String
    ) throws {
        if result < 0 {
            throw rtcError(operation: operation, result: result)
        }
    }

    func rtcError<T: BinaryInteger>(
        operation: String,
        result: T
    ) -> XmaxError {
        XmaxError(
            code: .rtcError,
            message: "\(operation) failed: \(result)"
        )
    }

    func validateVideoDimensions(
        width: Int,
        height: Int,
        frameRate: Int
    ) throws {
        guard width > 0, height > 0, frameRate > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video width, height, and frame rate must be positive"
            )
        }
    }

    func validateJoinConfiguration(
        _ configuration: RoomJoinConfiguration
    ) throws {
        guard !configuration.roomID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "RTC room ID cannot be empty"
            )
        }
        guard !configuration.userID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "RTC user ID cannot be empty"
            )
        }
    }

    static func cancelledError(operation: String) -> XmaxError {
        XmaxError(
            code: .cancelled,
            message: "\(operation) was cancelled"
        )
    }

    enum InitializationOutcome {
        case installed
        case alreadyInstalled
        case cancelled
    }
}
