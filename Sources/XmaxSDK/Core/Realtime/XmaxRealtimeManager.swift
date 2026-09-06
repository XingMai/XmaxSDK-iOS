import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 实时生成业务公共入口，统一编排本地媒体、连接、生成和状态通知。
actor XmaxRealtimeManager: XmaxRealtimeManaging {

    // 公共配置
    nonisolated let options: RealtimeConfiguration

    // 业务层组件
    private let renderController: any RenderControlling
    private let streamController: any StreamControlling
    private let mediaController: any MediaControlling

    // 服务层组件
    private let mediaService: any MediaServicing

    // 实时管理组件
    private let connectionManager: XmaxRealtimeConnectionManager
    private let generationManager: XmaxRealtimeGenerationManager
    private let errorHandler: RealtimeErrorHandler
    private let timing: RealtimeTiming

    // 并发控制
    private let coordinator: RealtimeCoordinator

    @MainActor
    init(
        options: RealtimeConfiguration,
        apiService: any ApiServicing
    ) {
        self.options = options

        let errorHandler = RealtimeErrorHandler()
        let rtcManager = RtcManager()
        let mediaService = MediaService()
        let timing = RealtimeTiming()

        let renderController = RenderController(
            rtcManager: rtcManager,
            frameInterpolationEnabled:
                options.isFrameInterpolationEnabled,
            frameInterpolationSupportChecker: {
                mediaService.supportsFrameInterpolation(for: $0)
            },
            errorListener: { errorHandler.forward($0) }
        )

        let streamController = StreamController(
            rtcManager: rtcManager,
            errorListener: { errorHandler.forward($0) },
            remoteStreamListener: { stream in
                try renderController.setRemoteStream(stream)
            },
            timing: timing
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
            streamController: streamController,
            timing: timing
        )

        let generationManager = XmaxRealtimeGenerationManager(
            interactionController: mediaController,
            streamController: streamController
        )
        let coordinator = RealtimeCoordinator(
            errorHandler: errorHandler,
            cleanup: { scope, taskID in
                await XmaxRealtimeManager.cleanup(
                    scope: scope,
                    taskID: taskID,
                    mediaController: mediaController,
                    connectionManager: connectionManager,
                    generationManager: generationManager
                )
            }
        )

        self.streamController = streamController
        self.mediaController = mediaController
        self.renderController = renderController
        self.mediaService = mediaService
        self.connectionManager = connectionManager
        self.errorHandler = errorHandler
        self.generationManager = generationManager
        self.timing = timing
        self.coordinator = coordinator
    }

    init(
        options: RealtimeConfiguration,
        streamController: any StreamControlling,
        mediaController: any MediaControlling,
        renderController: any RenderControlling,
        mediaService: any MediaServicing = MediaService(),
        connectionManager: XmaxRealtimeConnectionManager,
        errorHandler: RealtimeErrorHandler,
        generationManager: XmaxRealtimeGenerationManager,
        timing: RealtimeTiming = RealtimeTiming()
    ) {
        self.options = options
        self.streamController = streamController
        self.mediaController = mediaController
        self.renderController = renderController
        self.mediaService = mediaService
        self.connectionManager = connectionManager
        self.errorHandler = errorHandler
        self.generationManager = generationManager
        self.timing = timing
        coordinator = RealtimeCoordinator(
            errorHandler: errorHandler,
            cleanup: { scope, taskID in
                await XmaxRealtimeManager.cleanup(
                    scope: scope,
                    taskID: taskID,
                    mediaController: mediaController,
                    connectionManager: connectionManager,
                    generationManager: generationManager
                )
            }
        )
    }

    var currentState: RealtimeState {
        get async {
            await coordinator.currentState
        }
    }

    var isFrameInterpolationEnabled: Bool {
        get async {
            await renderController.isFrameInterpolationEnabled
        }
    }

    var localAudioVolume: Float {
        get async {
            await mediaController.localAudioVolume
        }
    }

    var remoteAudioVolume: Float {
        streamController.remoteAudioVolume
    }

    func setStateListener(_ listener: RealtimeStateListener?) async {
        await coordinator.setStateListener(listener)
    }

    func setErrorListener(_ listener: RealtimeErrorListener?) async {
        errorHandler.setListener(listener)
    }

    func setCameraPreviewReadyListener(
        _ listener: RealtimeCameraPreviewReadyListener?
    ) async {
        await mediaController.setCameraPreviewReadyListener(listener)
    }

    func setRemoteVideoFrameListener(
        _ listener: RealtimeVideoFrameListener?
    ) async {
        await renderController.setRemoteVideoFrameListener(listener)
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

    func setLocalAudioVolume(_ volume: Float) async throws {
        do {
            try Self.validateAudioVolume(volume)
            await mediaController.setLocalAudioVolume(volume)
        } catch {
            throw await reportError(error)
        }
    }

    func setRemoteAudioVolume(_ volume: Float) async throws {
        do {
            try Self.validateAudioVolume(volume)
            try streamController.setRemoteAudioVolume(volume)
        } catch {
            throw await reportError(
                XmaxError.from(error).withSeverity(.recoverable)
            )
        }
    }

    func setFrameInterpolationEnabled(_ enabled: Bool) async throws {
        do {
            let videoFormat = await mediaController.currentVideoFormat
            try await renderController.setFrameInterpolationEnabled(
                enabled,
                videoFormat: videoFormat
            )
        } catch {
            throw await reportError(
                XmaxError.from(error).withSeverity(.recoverable)
            )
        }
    }

    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        try await coordinator.run(
            kind: .media,
            failureScope: .all
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Local camera stream is unavailable during " +
                    "a realtime connection"
            )
            let stream = try await mediaController.createLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
            try token.ensureCurrent()
            await reconcileFrameInterpolation(for: stream)
            return stream
        }
    }

    func stopLocalCameraStream() async throws {
        try await coordinator.run(
            kind: .media,
            failureScope: .all
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Disconnect realtime before stopping the local " +
                    "camera stream"
            )
            await mediaController.stopLocalCameraStream()
            try token.ensureCurrent()
        }
    }

    func switchCamera() async throws -> RealtimeMediaStream {
        let current = await coordinator.currentState
        guard current.connectionState != .connecting,
              current.connectionState != .disconnecting else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Camera switching is unavailable while realtime " +
                        "is transitioning"
                )
            )
        }
        guard current.connectionState == .generating ||
                !streamController.hasGenerationTask else {
            throw await reportError(
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Camera switching is unavailable while " +
                        "realtime generation is starting"
                )
            )
        }

        return try await coordinator.run(
            kind: .cameraSwitch,
            failureScope: .connection
        ) { [self] token in
            let current = await coordinator.currentState
            guard current.connectionState != .connecting,
                  current.connectionState != .disconnecting else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Camera switching is unavailable while realtime " +
                        "is transitioning"
                )
            }

            let wasGenerating = current.connectionState == .generating
            guard wasGenerating || !streamController.hasGenerationTask else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Camera switching is unavailable while " +
                        "realtime generation is starting"
                )
            }

            if wasGenerating {
                try await generationManager.stop(
                    taskID: current.taskID ?? ""
                )
                await mediaController.setLocalAudioPreviewMuted(false)
                try await coordinator.commit(
                    RealtimeState(
                        connectionState: .connected,
                        sessionID: current.sessionID
                    ),
                    token: token
                )
            }

            let stream = try await mediaController.switchCamera()
            try token.ensureCurrent()
            await reconcileFrameInterpolation(for: stream)
            if wasGenerating {
                try await Task.sleep(nanoseconds: 500_000_000)
                try await performStartGeneration(
                    context: nil,
                    token: token
                )
            }
            return stream
        }
    }

    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await coordinator.run(
            kind: .media,
            failureScope: .all
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Local image stream is unavailable during " +
                    "a realtime connection"
            )
            let stream = try await mediaController.createLocalImageStream(
                imageData: imageData,
                videoFormat: videoFormat
            )
            try token.ensureCurrent()
            await reconcileFrameInterpolation(for: stream)
            return stream
        }
    }

#if canImport(UIKit)
    /// 从 UIKit 图片创建持续输出帧的媒体流。
    ///
    /// - Parameters:
    ///   - image: 用作本地输入的 UIKit 图片。
    ///   - videoFormat: 输出视频规格；传入 `nil` 时根据图片原始尺寸生成。
    func createLocalImageStream(
        image: UIImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let decodedImage = try ImageManager().decode(image)
        return try await createLocalImageStream(
            decodedImage: decodedImage,
            videoFormat: videoFormat
        )
    }
#endif

    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await coordinator.run(
            kind: .media,
            failureScope: .all
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Local image stream is unavailable during " +
                    "a realtime connection"
            )
            let stream = try await mediaController.createLocalImageStream(
                decodedImage: decodedImage,
                videoFormat: videoFormat
            )
            try token.ensureCurrent()
            await reconcileFrameInterpolation(for: stream)
            return stream
        }
    }

    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await coordinator.run(
            kind: .media,
            failureScope: .all
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Local image stream is unavailable during " +
                    "a realtime connection"
            )
            let stream = try await mediaController.createLocalImageStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
            try token.ensureCurrent()
            await reconcileFrameInterpolation(for: stream)
            return stream
        }
    }

    func stopLocalImageStream() async throws {
        try await coordinator.run(
            kind: .media,
            failureScope: .all
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Disconnect realtime before stopping the local " +
                    "image stream"
            )
            await mediaController.stopLocalImageStream()
            try token.ensureCurrent()
        }
    }

    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await coordinator.run(
            kind: .media,
            failureScope: .all
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Local video stream is unavailable during " +
                    "a realtime connection"
            )
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
                try token.ensureCurrent()
                await reconcileFrameInterpolation(for: stream)
                return stream
            } catch {
                await mediaController.stopLocalVideoStream()
                throw error
            }
        }
    }

    func stopLocalVideoStream() async throws {
        try await coordinator.run(
            kind: .media,
            failureScope: .all
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Disconnect realtime before stopping the local " +
                    "video stream"
            )
            await mediaController.stopLocalVideoStream()
            try token.ensureCurrent()
        }
    }

    func connect(
        localStream: RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        try await coordinator.run(
            kind: .connection,
            failureScope: .connection
        ) { [self] token in
            try await performConnect(
                localStream: localStream,
                token: token
            )
        }
    }

    func disconnect() async {
        let current = await coordinator.currentState
        guard current.connectionState != .idle,
              current.connectionState != .disconnected else {
            return
        }
        await coordinator.terminate(
            .connection,
            finalState: .disconnected
        )
    }

    func close() async {
        await coordinator.terminate(
            .all,
            finalState: .disconnected
        )
    }

    func startGeneration(context: RealtimeContext?) async throws {
        let current = await coordinator.currentState
        let measuresStartup = current.connectionState == .connected
        if measuresStartup {
            timing.begin()
        }
        do {
            try await coordinator.run(
                kind: .generation,
                failureScope: .generation
            ) { [self] token in
                try await performStartGeneration(
                    context: context,
                    token: token
                )
            }
        } catch {
            if measuresStartup {
                timing.finishFailure(error)
            }
            throw error
        }
    }

    func startGeneration(
        localStream: RealtimeMediaStream,
        context: RealtimeContext?
    ) async throws -> RealtimeMediaStream {
        let initialState = await coordinator.currentState
        let hasConnection = await connectionManager.currentSessionID != ""
        let failureScope: RealtimeCoordinator.TerminationScope =
            hasConnection ? .generation : .connection
        let measuresStartup = initialState.connectionState != .connecting &&
            initialState.connectionState != .disconnecting
        if measuresStartup {
            timing.begin()
        }
        do {
            return try await coordinator.run(
                kind: .generation,
                failureScope: failureScope
            ) { [self] token in
                guard await mediaController.owns(localStream) else {
                    throw XmaxError(
                        code: .invalidConfiguration,
                        message: "The local stream must be created and " +
                            "started by this realtime manager"
                    )
                }

                let remoteStream: RealtimeMediaStream
                if await connectionManager.currentSessionID != "" {
                    guard let activeRemoteStream =
                            await connectionManager.currentRemoteStream else {
                        throw XmaxError(
                            code: .rtcError,
                            message: "Realtime connection has no remote stream"
                        )
                    }
                    remoteStream = activeRemoteStream
                } else {
                    await mediaController.setLocalAudioPreviewMuted(true)
                    remoteStream = try await performConnect(
                        localStream: localStream,
                        token: token
                    )
                    token.setFailureScope(.generation)
                }

                try await performStartGeneration(
                    context: context,
                    token: token
                )
                return remoteStream
            }
        } catch {
            if measuresStartup {
                timing.finishFailure(error)
            }
            throw error
        }
    }

    private func performStartGeneration(
        context: RealtimeContext?,
        token: RealtimeCoordinator.Token
    ) async throws {
        try token.ensureCurrent()
        let sessionID = await connectionManager.currentSessionID
        var current = await coordinator.currentState
        if current.connectionState == .error, !sessionID.isEmpty {
            current = RealtimeState(
                connectionState: .connected,
                sessionID: sessionID
            )
            try await coordinator.commit(current, token: token)
        }
        guard !sessionID.isEmpty,
              current.connectionState == .connected ||
                current.connectionState == .generating,
              let videoFormat = await mediaController.currentVideoFormat else {
            throw XmaxError(
                code: .rtcError,
                message: "Realtime connection is not open",
                severity: .recoverable
            )
        }

        if current.connectionState == .generating,
           let taskID = current.taskID {
            try await generationManager.update(
                taskID: taskID,
                videoFormat: videoFormat,
                context: context
            )
            try token.ensureCurrent()
            return
        }

        do {
            await mediaController.setLocalAudioPreviewMuted(true)
            let taskID = try await generationManager.start(
                videoFormat: videoFormat,
                context: context,
                ensureCurrent: {
                    try token.ensureCurrent()
                }
            )
            try await renderController.waitUntilRemoteFrameReady()
            try token.ensureCurrent()
            try streamController.activateRemoteAudio()
            guard await connectionManager.currentSessionID == sessionID else {
                throw XmaxError(
                    code: .cancelled,
                    message: "Realtime connection was cancelled"
                )
            }
            try await coordinator.commit(
                RealtimeState(
                    connectionState: .generating,
                    sessionID: sessionID,
                    taskID: taskID
                ),
                token: token
            )
            timing.finish(taskID: taskID)
        } catch {
            await mediaController.setLocalAudioPreviewMuted(false)
            throw error
        }
    }

    func stopGeneration() async {
        let current = await coordinator.currentState
        let sessionID = await connectionManager.currentSessionID
        guard !sessionID.isEmpty,
              current.connectionState == .connected ||
                current.connectionState == .generating else {
            return
        }
        await coordinator.terminate(.generation)
    }
}

private extension XmaxRealtimeManager {
    func performConnect(
        localStream: RealtimeMediaStream,
        token: RealtimeCoordinator.Token
    ) async throws -> RealtimeMediaStream {
        let current = await coordinator.currentState
        guard await connectionManager.currentSessionID == "",
              current.connectionState != .connecting,
              current.connectionState != .disconnecting else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Realtime connection is already open"
            )
        }
        guard let videoFormat = localStream.videoTrack?.videoFormat,
              await mediaController.owns(localStream) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "The local stream must be created and started " +
                    "by this realtime manager"
            )
        }

        try await generationManager.reset()
        try token.ensureCurrent()
        try await coordinator.commit(
            RealtimeState(connectionState: .connecting),
            token: token
        )
        try streamController.setVideoEncoderConfig(videoFormat)
        let remoteStream = try await connectionManager.connect(
            model: options.model,
            videoFormat: videoFormat,
            includeLocalAudio: await mediaController.hasAudio,
            isCurrent: { token.isCurrent },
            onHeartbeatFailure: { [weak self] sessionID, error in
                await self?.handleHeartbeatFailure(
                    sessionID: sessionID,
                    error: error
                )
            }
        )
        try token.ensureCurrent()
        let sessionID = await connectionManager.currentSessionID
        guard !sessionID.isEmpty else {
            throw XmaxError(
                code: .cancelled,
                message: "Realtime connection was cancelled"
            )
        }

        try await coordinator.commit(
            RealtimeState(
                connectionState: .connected,
                sessionID: sessionID
            ),
            token: token
        )
        return remoteStream
    }

    func ensureLocalMediaCanChange(message: String) async throws {
        let current = await coordinator.currentState
        guard await connectionManager.currentSessionID == "",
              current.connectionState != .connecting,
              current.connectionState != .disconnecting else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: message
            )
        }
    }

    func reconcileFrameInterpolation(
        for stream: RealtimeMediaStream
    ) async {
        guard await renderController.isFrameInterpolationEnabled,
              let videoFormat = stream.videoTrack?.videoFormat else {
            return
        }
        let size = CGSize(
            width: videoFormat.width,
            height: videoFormat.height
        )
        guard !mediaService.supportsFrameInterpolation(for: size) else {
            return
        }

        try? await renderController.setFrameInterpolationEnabled(
            false,
            videoFormat: videoFormat
        )
        await errorHandler.report(
            XmaxError(
                code: .frameInterpolationUnsupported,
                message: "Frame interpolation is unavailable for " +
                    "\(videoFormat.width) × \(videoFormat.height) video",
                severity: .recoverable
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
        await coordinator.terminate(
            with: error,
            target: .connection
        )
    }

    @discardableResult
    func reportError(_ error: any Error) async -> XmaxError {
        let xmaxError = XmaxError.from(error)
        await errorHandler.report(xmaxError)
        return xmaxError
    }

    static func validateAudioVolume(_ volume: Float) throws {
        guard volume.isFinite, (0...1).contains(volume) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Audio volume must be between 0 and 1"
            )
        }
    }

    nonisolated static func cleanup(
        scope: RealtimeCoordinator.TerminationScope,
        taskID: String,
        mediaController: any MediaControlling,
        connectionManager: XmaxRealtimeConnectionManager,
        generationManager: XmaxRealtimeGenerationManager
    ) async -> RealtimeCoordinator.CleanupResult {
        let releasesConnection = scope.includes(.connection)
        if scope == .all {
            await mediaController.setLocalAudioPreviewMuted(true)
        }

        do {
            if releasesConnection {
                try await generationManager.reset(taskID: taskID)
            } else {
                try await generationManager.stop(taskID: taskID)
            }
        } catch {
            logCleanupFailure(
                title: "停止实时生成失败 " +
                    "(Failed to Stop Realtime Generation)",
                error: error
            )
        }

        var sessionID: String?
        if releasesConnection {
            let activeSessionID = await connectionManager.currentSessionID
            sessionID = activeSessionID.isEmpty ? nil : activeSessionID
            do {
                sessionID = try await connectionManager.disconnect() ?? sessionID
            } catch {
                logCleanupFailure(
                    title: "断开实时连接失败 " +
                        "(Failed to Disconnect Realtime)",
                    error: error
                )
            }
        }

        if scope == .all {
            await mediaController.stopLocalStream()
        } else {
            await mediaController.setLocalAudioPreviewMuted(false)
        }
        return RealtimeCoordinator.CleanupResult(sessionID: sessionID)
    }

    nonisolated static func logCleanupFailure(
        title: String,
        error: any Error
    ) {
        XmaxLogger.error(
            category: "Realtime",
            message: "\(title)\n└─ 原因：" +
                (error as NSError).localizedDescription
        )
    }
}
