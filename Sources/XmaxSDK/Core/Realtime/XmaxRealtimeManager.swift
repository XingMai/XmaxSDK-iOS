import Foundation

/// 实时生成业务公共入口，统一编排本地媒体、连接、生成和状态通知。
actor XmaxRealtimeManager: XmaxRealtimeManaging {

    // 公共配置
    nonisolated let options: RealtimeConfiguration

    // 媒体层组件
    private let mediaController: any MediaControlling

    // 传输层组件
    private let streamController: any StreamControlling

    // 实时管理组件
    private let connectionManager: XmaxRealtimeConnectionManager
    private let errorHandler: RealtimeErrorHandler
    private let generationManager: XmaxRealtimeGenerationManager

    // 并发控制
    private let operationVersion = RealtimeOperationVersion()

    // 事件监听
    private var stateListener: RealtimeStateListener?

    // 运行状态
    private var state = RealtimeState(connectionState: .idle)
    private var terminationOperation: TerminationOperation?
    private var terminationFinalState: RealtimeConnectionState?

    @MainActor
    init(
        options: RealtimeConfiguration,
        apiService: any ApiServicing
    ) {
        self.options = options

        let errorHandler = RealtimeErrorHandler()
        let rtcManager = RtcManager()

        let renderController = RenderController(
            rtcManager: rtcManager,
            errorListener: { errorHandler.forward($0) }
        )

        let streamController = StreamController(
            rtcManager: rtcManager,
            errorListener: { errorHandler.forward($0) },
            remoteStreamListener: { stream in
                try renderController.setRemoteStream(stream)
            }
        )

        let mediaController = MediaController(
            rtcManager: rtcManager,
            videoFrameListener: { frame in
                try streamController.pushLocalVideoFrame(frame)
            },
            audioFrameListener: { frame in
                try streamController.pushLocalAudioFrame(frame)
            },
            errorListener: { errorHandler.forward($0) },
            interactionListener: { taskID, points in
                try await streamController.sendTracks(
                    taskID: taskID,
                    points: points
                )
            }
        )

        let connectionManager = XmaxRealtimeConnectionManager(
            sessionService: RealtimeSessionService(apiService: apiService),
            interactionController: mediaController,
            renderController: renderController,
            streamController: streamController
        )

        let generationManager = XmaxRealtimeGenerationManager(
            interactionController: mediaController,
            streamController: streamController
        )

        self.streamController = streamController
        self.mediaController = mediaController
        self.connectionManager = connectionManager
        self.errorHandler = errorHandler
        self.generationManager = generationManager
    }

    init(
        options: RealtimeConfiguration,
        streamController: any StreamControlling,
        mediaController: any MediaControlling,
        connectionManager: XmaxRealtimeConnectionManager,
        errorHandler: RealtimeErrorHandler,
        generationManager: XmaxRealtimeGenerationManager
    ) {
        self.options = options
        self.streamController = streamController
        self.mediaController = mediaController
        self.connectionManager = connectionManager
        self.errorHandler = errorHandler
        self.generationManager = generationManager
    }

    var currentState: RealtimeState {
        state
    }

    func setStateListener(_ listener: RealtimeStateListener?) async {
        stateListener = listener
        if let listener {
            await listener(state)
        }
    }

    func setErrorListener(_ listener: RealtimeErrorListener?) async {
        errorHandler.setListener(listener)
    }

    func setCameraPreviewReadyListener(
        _ listener: RealtimeCameraPreviewReadyListener?
    ) async {
        await mediaController.setCameraPreviewReadyListener(listener)
    }

    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) {
        streamController.setNetworkQualityListener(listener)
    }

    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) {
        streamController.setPerformanceAlarmListener(listener)
    }

    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local camera stream is unavailable during " +
                        "a realtime connection"
                )
            )
        }

        do {
            return try await mediaController.createLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
        } catch {
            throw await reportError(error)
        }
    }

    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        guard state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local camera update is unavailable while " +
                        "realtime is transitioning"
                )
            )
        }

        let hasConnection = await connectionManager.currentSessionID != ""
        if hasConnection {
            await stopGeneration()
        }

        do {
            let stream = try await mediaController.replaceLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
            if hasConnection {
                if let videoFormat = stream.videoTrack?.videoFormat {
                    try streamController.setVideoEncoderConfig(videoFormat)
                }
                await synchronizeConnectionAfterCameraUpdate(stream)
            }
            return stream
        } catch {
            throw await reportError(error)
        }
    }

    func stopLocalCameraStream() async throws {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Disconnect realtime before stopping the local " +
                        "camera stream"
                )
            )
        }
        await mediaController.stopLocalCameraStream()
    }

    func switchCamera() async throws -> RealtimeMediaStream {
        guard state.connectionState != .connecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Camera switching is unavailable while realtime " +
                        "is connecting"
                )
            )
        }
        do {
            return try await mediaController.switchCamera()
        } catch {
            throw await reportError(error)
        }
    }

    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local image stream is unavailable during " +
                        "a realtime connection"
                )
            )
        }

        do {
            return try await mediaController.createLocalImageStream(
                imageData: imageData,
                videoFormat: videoFormat
            )
        } catch {
            throw await reportError(error)
        }
    }

    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local image stream is unavailable during " +
                        "a realtime connection"
                )
            )
        }

        do {
            return try await mediaController.createLocalImageStream(
                decodedImage: decodedImage,
                videoFormat: videoFormat
            )
        } catch {
            throw await reportError(error)
        }
    }

    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local image stream is unavailable during " +
                        "a realtime connection"
                )
            )
        }

        do {
            return try await mediaController.createLocalImageStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
        } catch {
            throw await reportError(error)
        }
    }

    func stopLocalImageStream() async throws {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Disconnect realtime before stopping the local " +
                        "image stream"
                )
            )
        }
        await mediaController.stopLocalImageStream()
    }

    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local video stream is unavailable during " +
                        "a realtime connection"
                )
            )
        }

        do {
            let stream = try await mediaController.createLocalVideoStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
            do {
                guard let resolvedFormat = stream.videoTrack?.videoFormat else {
                    throw XmaxError(
                        code: .internalError,
                        message: "Local video stream has no video format"
                    )
                }
                try streamController.setVideoEncoderConfig(resolvedFormat)
                return stream
            } catch {
                await mediaController.stopLocalVideoStream()
                throw error
            }
        } catch {
            throw await reportError(error)
        }
    }

    func stopLocalVideoStream() async throws {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Disconnect realtime before stopping the local " +
                        "video stream"
                )
            )
        }
        await mediaController.stopLocalVideoStream()
    }

    func connect(
        localStream: RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        guard await connectionManager.currentSessionID == "",
              state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Realtime connection is already open"
                )
            )
        }
        guard let videoFormat = localStream.videoTrack?.videoFormat,
              await mediaController.owns(localStream) else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "The local stream must be created and started " +
                        "by this realtime manager"
                )
            )
        }

        do {
            try await generationManager.reset()
        } catch {
            throw await reportError(error)
        }
        let version = operationVersion.advance()
        await emitState(RealtimeState(connectionState: .connecting))

        do {
            try ensureOperation(version)
            try streamController.setVideoEncoderConfig(videoFormat)
            let remoteStream = try await connectionManager.connect(
                model: options.model,
                videoFormat: videoFormat,
                includeLocalAudio: await mediaController.hasAudio,
                isCurrent: { [operationVersion] in
                    operationVersion.isCurrent(version)
                },
                onHeartbeatFailure: { [weak self] sessionID, error in
                    await self?.handleHeartbeatFailure(
                        sessionID: sessionID,
                        error: error
                    )
                }
            )
            try ensureOperation(version)
            let sessionID = await connectionManager.currentSessionID
            guard !sessionID.isEmpty else {
                throw XmaxError(
                    code: .cancelled,
                    message: "Realtime connection was cancelled"
                )
            }

            await emitState(
                RealtimeState(
                    connectionState: .connected,
                    sessionID: sessionID
                )
            )
            try ensureOperation(version)
            return remoteStream
        } catch {
            guard operationVersion.isCurrent(version) else {
                throw XmaxError(
                    code: .cancelled,
                    message: "Realtime connection was cancelled"
                )
            }
            let xmaxError = await reportError(error)
            await emitState(RealtimeState(connectionState: .error))
            throw xmaxError
        }
    }

    func disconnect() async {
        if terminationOperation != nil {
            terminationFinalState = .disconnected
            await terminationOperation?.task.value
            return
        }
        guard state.connectionState != .idle,
              state.connectionState != .disconnected else {
            return
        }
        await beginTermination(finalState: .disconnected)
    }

    func startGeneration(context: RealtimeContext?) async throws {
        try await performStartGeneration(context: context)
    }

    func startGeneration(
        localStream: RealtimeMediaStream,
        context: RealtimeContext?
    ) async throws -> RealtimeMediaStream {
        guard await mediaController.owns(localStream) else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "The local stream must be created and started " +
                        "by this realtime manager"
                )
            )
        }

        if state.connectionState == .connected ||
            state.connectionState == .generating {
            guard let remoteStream =
                    await connectionManager.currentRemoteStream else {
                throw await reportError(
                    XmaxError(
                        code: .rtcError,
                        message: "Realtime connection has no remote stream"
                    )
                )
            }
            try await startGeneration(context: context)
            return remoteStream
        }

        do {
            await mediaController.setLocalAudioPreviewMuted(true)
            let remoteStream = try await connect(localStream: localStream)
            try await performStartGeneration(context: context)
            return remoteStream
        } catch {
            await unmuteLocalAudioPreview()
            throw error
        }
    }

    private func performStartGeneration(
        context: RealtimeContext?
    ) async throws {
        let sessionID = await connectionManager.currentSessionID
        guard !sessionID.isEmpty,
              state.connectionState == .connected ||
                state.connectionState == .generating,
              let videoFormat = await mediaController.currentVideoFormat else {
            throw await reportError(
                XmaxError(
                    code: .rtcError,
                    message: "Realtime connection is not open"
                )
            )
        }

        if state.connectionState == .generating,
           let taskID = state.taskID {
            do {
                try await generationManager.update(
                    taskID: taskID,
                    videoFormat: videoFormat,
                    context: context
                )
                return
            } catch {
                throw await reportError(error)
            }
        }

        let version = operationVersion.current
        do {
            await mediaController.setLocalAudioPreviewMuted(true)
            let taskID = try await generationManager.start(
                videoFormat: videoFormat,
                context: context,
                ensureCurrent: { [operationVersion] in
                    guard operationVersion.isCurrent(version) else {
                        throw XmaxError(
                            code: .cancelled,
                            message: "Realtime connection was cancelled"
                        )
                    }
                }
            )
            guard operationVersion.isCurrent(version),
                  await connectionManager.currentSessionID == sessionID else {
                throw XmaxError(
                    code: .cancelled,
                    message: "Realtime connection was cancelled"
                )
            }
            await emitState(
                RealtimeState(
                    connectionState: .generating,
                    sessionID: sessionID,
                    taskID: taskID
                )
            )
        } catch {
            await unmuteLocalAudioPreview()
            throw await reportError(error)
        }
    }

    func stopGeneration() async {
        let sessionID = await connectionManager.currentSessionID
        guard !sessionID.isEmpty,
              state.connectionState == .connected ||
                state.connectionState == .generating else {
            return
        }

        let version = operationVersion.current
        let wasGenerating = state.connectionState == .generating
        do {
            try await generationManager.stop(taskID: state.taskID ?? "")
        } catch {
            await reportError(error)
        }
        await unmuteLocalAudioPreview()
        if wasGenerating, operationVersion.isCurrent(version) {
            await emitState(
                RealtimeState(
                    connectionState: .connected,
                    sessionID: sessionID
                )
            )
        }
    }
}

private extension XmaxRealtimeManager {
    struct TerminationOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    func synchronizeConnectionAfterCameraUpdate(
        _ stream: RealtimeMediaStream
    ) async {
        do {
            try streamController.setLocalAudioEnabled(
                await mediaController.hasAudio
            )
        } catch {
            await reportError(error)
        }
        if let videoFormat = stream.videoTrack?.videoFormat {
            await connectionManager.updateRemoteVideoFormat(videoFormat)
        }
    }

    func beginTermination(
        finalState: RealtimeConnectionState
    ) async {
        if let terminationOperation {
            if finalState == .disconnected {
                terminationFinalState = .disconnected
            }
            await terminationOperation.task.value
            return
        }

        operationVersion.advance()
        terminationFinalState = finalState
        let operationID = UUID()
        let taskID = state.taskID ?? ""
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performTermination(
                operationID: operationID,
                taskID: taskID
            )
        }
        terminationOperation = TerminationOperation(
            id: operationID,
            task: task
        )
        await emitState(RealtimeState(connectionState: .disconnecting))
        await task.value
    }

    func performTermination(
        operationID: UUID,
        taskID: String
    ) async {
        do {
            try await generationManager.reset(taskID: taskID)
        } catch {
            await reportError(error)
        }
        let activeSessionID = await connectionManager.currentSessionID
        var sessionID: String? = activeSessionID.isEmpty
            ? nil
            : activeSessionID
        do {
            sessionID = try await connectionManager.disconnect()
        } catch {
            await reportError(error)
        }
        await unmuteLocalAudioPreview()
        guard terminationOperation?.id == operationID else {
            return
        }

        let finalState = terminationFinalState ?? .error
        terminationOperation = nil
        terminationFinalState = nil
        await emitState(
            RealtimeState(
                connectionState: finalState,
                sessionID: sessionID
            )
        )
    }

    func handleHeartbeatFailure(
        sessionID: String,
        error: XmaxError
    ) async {
        guard await connectionManager.currentSessionID == sessionID else {
            return
        }
        await reportError(error)
        guard await connectionManager.currentSessionID == sessionID else {
            return
        }
        await beginTermination(finalState: .error)
    }

    func ensureOperation(_ version: UInt64) throws {
        guard operationVersion.isCurrent(version) else {
            throw XmaxError(
                code: .cancelled,
                message: "Realtime connection was cancelled"
            )
        }
    }

    func emitState(_ state: RealtimeState) async {
        self.state = state
        if let stateListener {
            await stateListener(state)
        }
    }

    @discardableResult
    func reportError(_ error: any Error) async -> XmaxError {
        let xmaxError = XmaxError.from(error)
        await errorHandler.report(xmaxError)
        return xmaxError
    }

    func unmuteLocalAudioPreview() async {
        await mediaController.setLocalAudioPreviewMuted(false)
    }
}

/// 提供可从同步有效性回调读取的连接生命周期版本。
private final class RealtimeOperationVersion: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var value: UInt64 = 0

    var current: UInt64 {
        lock.withLock { value }
    }

    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    func isCurrent(_ version: UInt64) -> Bool {
        lock.withLock { value == version }
    }
}
