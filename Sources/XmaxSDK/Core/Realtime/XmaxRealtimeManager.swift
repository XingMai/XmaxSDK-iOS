import Foundation

/// 实时生成业务公共入口，统一编排本地媒体、连接、生成和状态通知。
actor XmaxRealtimeManager: XmaxRealtimeManaging {

    // 公共配置
    nonisolated let options: RealtimeConfiguration

    // 业务层组件
    private let qualityController: any QualityControlling
    private let streamController: any StreamControlling

    // 实时管理组件
    private let mediaManager: XmaxRealtimeMediaManager
    private let connectionManager: XmaxRealtimeConnectionManager
    private let generationManager: XmaxRealtimeGenerationManager

    // 并发控制
    private let operationVersion = RealtimeOperationVersion()

    // 事件监听
    private var errorListener: RealtimeErrorListener?
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

        let rtcProvider = RtcProvider()
        let roomController = RoomController(rtcProvider: rtcProvider)
        let remoteVideoController = RemoteVideoController(
            rtcProvider: rtcProvider
        )
        let streamController = StreamController(
            rtcProvider: rtcProvider,
            remoteStreamListener: { stream in
                try remoteVideoController.setRemoteStream(stream)
            }
        )
        let qualityController = QualityController(rtcProvider: rtcProvider)
        let mediaErrorRelay = RealtimeMediaErrorRelay()
        let mediaManager = XmaxRealtimeMediaManager(
            rtcProvider: rtcProvider,
            streamController: streamController,
            mediaErrorListener: { error in
                mediaErrorRelay.report(error)
            }
        )
        let connectionManager = XmaxRealtimeConnectionManager(
            rtcProvider: rtcProvider,
            sessionService: RealtimeSessionService(apiService: apiService),
            roomController: roomController,
            remoteVideoController: remoteVideoController,
            streamController: streamController
        )
        let generationManager = XmaxRealtimeGenerationManager(
            roomController: roomController,
            streamController: streamController
        )

        self.qualityController = qualityController
        self.streamController = streamController
        self.mediaManager = mediaManager
        self.connectionManager = connectionManager
        self.generationManager = generationManager

        mediaErrorRelay.setListener { [weak self] error in
            Task {
                _ = await self?.reportError(error)
            }
        }
    }

    init(
        options: RealtimeConfiguration,
        qualityController: any QualityControlling,
        streamController: any StreamControlling,
        mediaManager: XmaxRealtimeMediaManager,
        connectionManager: XmaxRealtimeConnectionManager,
        generationManager: XmaxRealtimeGenerationManager
    ) {
        self.options = options
        self.qualityController = qualityController
        self.streamController = streamController
        self.mediaManager = mediaManager
        self.connectionManager = connectionManager
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
        errorListener = listener
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
            return try await mediaManager.createLocalCameraStream(
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
                    message: "Local media replacement is unavailable while " +
                        "realtime is transitioning"
                )
            )
        }

        let hasConnection = await connectionManager.currentSessionID != ""
        if hasConnection {
            await stopGeneration()
        }

        do {
            let stream = try await mediaManager.replaceLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
            if hasConnection {
                await synchronizeConnectionAfterReplacement(stream)
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
        await mediaManager.stopLocalCameraStream()
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
            return try await mediaManager.switchCamera()
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
            return try await mediaManager.createLocalImageStream(
                imageData: imageData,
                videoFormat: videoFormat
            )
        } catch {
            throw await reportError(error)
        }
    }

    func replaceLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local media replacement is unavailable while " +
                        "realtime is transitioning"
                )
            )
        }

        let hasConnection = await connectionManager.currentSessionID != ""
        if hasConnection {
            await stopGeneration()
        }

        do {
            let stream = try await mediaManager.replaceLocalImageStream(
                imageData: imageData,
                videoFormat: videoFormat
            )
            if hasConnection {
                await synchronizeConnectionAfterReplacement(stream)
            }
            return stream
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
            return try await mediaManager.createLocalImageStream(
                decodedImage: decodedImage,
                videoFormat: videoFormat
            )
        } catch {
            throw await reportError(error)
        }
    }

    func replaceLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local media replacement is unavailable while " +
                        "realtime is transitioning"
                )
            )
        }

        let hasConnection = await connectionManager.currentSessionID != ""
        if hasConnection {
            await stopGeneration()
        }

        do {
            let stream = try await mediaManager.replaceLocalImageStream(
                decodedImage: decodedImage,
                videoFormat: videoFormat
            )
            if hasConnection {
                await synchronizeConnectionAfterReplacement(stream)
            }
            return stream
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
            return try await mediaManager.createLocalImageStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
        } catch {
            throw await reportError(error)
        }
    }

    func replaceLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local media replacement is unavailable while " +
                        "realtime is transitioning"
                )
            )
        }

        let hasConnection = await connectionManager.currentSessionID != ""
        if hasConnection {
            await stopGeneration()
        }

        do {
            let stream = try await mediaManager.replaceLocalImageStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
            if hasConnection {
                await synchronizeConnectionAfterReplacement(stream)
            }
            return stream
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
        await mediaManager.stopLocalImageStream()
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
            return try await mediaManager.createLocalVideoStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
        } catch {
            throw await reportError(error)
        }
    }

    func replaceLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard state.connectionState != .connecting,
              state.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Local media replacement is unavailable while " +
                        "realtime is transitioning"
                )
            )
        }

        let hasConnection = await connectionManager.currentSessionID != ""
        if hasConnection {
            await stopGeneration()
        }

        do {
            let stream = try await mediaManager.replaceLocalVideoStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
            if hasConnection {
                await synchronizeConnectionAfterReplacement(stream)
            }
            return stream
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
        await mediaManager.stopLocalVideoStream()
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
              await mediaManager.owns(localStream) else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "The local stream must be created and started " +
                        "by this realtime manager"
                )
            )
        }

        await generationManager.reset()
        let version = operationVersion.advance()
        await emitState(RealtimeState(connectionState: .connecting))

        do {
            try ensureOperation(version)
            let remoteStream = try await connectionManager.connect(
                model: options.model,
                videoFormat: videoFormat,
                includeLocalAudio: await mediaManager.hasAudio,
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
        let sessionID = await connectionManager.currentSessionID
        guard !sessionID.isEmpty,
              state.connectionState == .connected ||
                state.connectionState == .generating,
              let videoFormat = await mediaManager.currentVideoFormat else {
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
                },
                onGenerationStarted: { [mediaManager] in
                    try await mediaManager.restartForGeneration()
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
        await generationManager.stop(taskID: state.taskID ?? "")
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

    func synchronizeConnectionAfterReplacement(
        _ stream: RealtimeMediaStream
    ) async {
        do {
            try streamController.setLocalAudioEnabled(
                await mediaManager.hasAudio
            )
        } catch {
            _ = await reportError(error)
        }
        if let videoFormat = stream.videoTrack?.videoFormat {
            await connectionManager.updateRemoteVideoFormat(videoFormat)
        }
    }

    func beginTermination(
        finalState: RealtimeConnectionState,
        fallbackSessionID: String? = nil
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
                taskID: taskID,
                fallbackSessionID: fallbackSessionID
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
        taskID: String,
        fallbackSessionID: String?
    ) async {
        await generationManager.reset(taskID: taskID)
        let sessionID = await connectionManager.disconnect(
            fallbackSessionID: fallbackSessionID
        )
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
        _ = await reportError(error)
        await beginTermination(
            finalState: .error,
            fallbackSessionID: sessionID
        )
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

    func reportError(_ error: any Error) async -> XmaxError {
        let xmaxError = XmaxError.from(error)
        if let errorListener {
            await errorListener(xmaxError)
        }
        return xmaxError
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

/// 将同步媒体回调安全转发给实时 Manager 的异步错误监听器。
private final class RealtimeMediaErrorRelay: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 事件监听
    private var listener: (@Sendable (XmaxError) -> Void)?

    func setListener(
        _ listener: @escaping @Sendable (XmaxError) -> Void
    ) {
        lock.withLock {
            self.listener = listener
        }
    }

    func report(_ error: XmaxError) {
        let listener = lock.withLock { listener }
        listener?(error)
    }
}
