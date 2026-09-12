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
        let mediaService = MediaService(model: options.model)
        let timing = RealtimeTiming()

        let renderController = RenderController(
            rtcManager: rtcManager,
            frameInterpolationEnabled:
                options.isFrameInterpolationEnabled,
            frameInterpolationSupportChecker: {
                mediaService.supportsFrameInterpolation(for: $0)
            },
            errorListener: { errorHandler.forward($0, target: .connection) }
        )

        let streamController = StreamController(
            rtcManager: rtcManager,
            errorListener: { errorHandler.forward($0, target: .connection) },
            remoteStreamListener: { stream in
                try renderController.setRemoteStream(stream)
            },
            timing: timing
        )

        let mediaController = MediaController(
            rtcManager: rtcManager,
            mediaService: mediaService,
            videoFrameListener: { frame in
                try streamController.pushLocalVideoFrame(frame)
            },
            audioFrameListener: { frame in
                try streamController.pushLocalAudioFrame(frame)
            },
            errorListener: { errorHandler.forward($0, target: .all) },
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
        errorHandler.setFailureHandler { [weak coordinator] error, target, isCurrent in
            await coordinator?.terminate(with: error, target: target, isCurrent: isCurrent)
        }
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
        self.coordinator = coordinator
        errorHandler.setFailureHandler { [weak coordinator] error, target, isCurrent in
            await coordinator?.terminate(with: error, target: target, isCurrent: isCurrent)
        }
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
        try await coordinator.run(
            kind: .configuration
        ) { [self] token in
            do {
                let current = await coordinator.currentState
                let generationFormat = await mediaController.currentVideoFormat
                let targetSize = try generationFormat.map {
                    enabled ? try mediaService.resolveFrameInterpolationSize($0.size) : $0.size
                }
                if enabled, let targetSize,
                   !mediaService.supportsFrameInterpolation(for: targetSize) {
                    throw XmaxError(
                        code: .frameInterpolationUnsupported,
                        message: "Frame interpolation is unavailable for " +
                            "\(Int(targetSize.width)) × \(Int(targetSize.height)) video",
                        severity: .recoverable
                    )
                }
                try token.ensureCurrent()
                if let taskID = current.taskID, let targetSize {
                    try await streamController.changeTargetSize(
                        taskID: taskID,
                        targetSize: targetSize,
                        ensureActive: { try token.ensureCurrent() }
                    )
                }

                // 信令发出后完成本地配置提交；并发断开会等待当前操作完成再清理。
                if let generationFormat, let targetSize {
                    await connectionManager.updateTargetSize(targetSize, videoFormat: generationFormat)
                }
                var returnFormat = generationFormat
                if let generationFormat, let targetSize {
                    returnFormat = generationFormat.resized(
                        width: Int(targetSize.width),
                        height: Int(targetSize.height)
                    )
                }
                try await renderController.setFrameInterpolationEnabled(
                    enabled,
                    videoFormat: returnFormat
                )
            } catch {
                throw XmaxError.from(error).withSeverity(.recoverable)
            }
        }
    }

    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition,
        useMicrophone: Bool = false
    ) async throws -> RealtimeMediaStream {
        try await createLocalMediaStream(source: .camera) { [self] token in
            let stream = try await mediaController.createLocalCameraStream(
                videoFormat: videoFormat,
                position: position,
                useMicrophone: useMicrophone
            )
            try token.ensureCurrent()
            return stream
        }
    }

    func stopLocalCameraStream() async throws {
        try await coordinator.run(
            kind: .media
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Disconnect realtime before stopping the local " +
                    "camera stream"
            )
            token.setFailureScope(.all)
            await mediaController.stopLocalCameraStream()
            try token.ensureCurrent()
            errorHandler.invalidatePendingFailures()
            let hasLocalMedia = await mediaController.currentTrack != nil
            try await coordinator.commit(
                RealtimeState(connectionState: hasLocalMedia ? .ready : .idle), token: token
            )
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
            kind: .cameraSwitch
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
                token.setFailureScope(.connection)
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
        try await createLocalMediaStream(source: .image) { [self] token in
            let stream = try await mediaController.createLocalImageStream(
                imageData: imageData,
                videoFormat: videoFormat
            )
            try token.ensureCurrent()
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
        try await createLocalMediaStream(source: .image) { [self] token in
            let stream = try await mediaController.createLocalImageStream(
                decodedImage: decodedImage,
                videoFormat: videoFormat
            )
            try token.ensureCurrent()
            return stream
        }
    }

    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await createLocalMediaStream(source: .image) { [self] token in
            let stream = try await mediaController.createLocalImageStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
            try token.ensureCurrent()
            return stream
        }
    }

    func stopLocalImageStream() async throws {
        try await coordinator.run(
            kind: .media
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Disconnect realtime before stopping the local " +
                    "image stream"
            )
            token.setFailureScope(.all)
            await mediaController.stopLocalImageStream()
            try token.ensureCurrent()
            errorHandler.invalidatePendingFailures()
            let hasLocalMedia = await mediaController.currentTrack != nil
            try await coordinator.commit(
                RealtimeState(connectionState: hasLocalMedia ? .ready : .idle), token: token
            )
        }
    }

    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await createLocalMediaStream(source: .video) { [self] token in
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
                return stream
            } catch {
                await mediaController.stopLocalVideoStream()
                throw error
            }
        }
    }

    func stopLocalVideoStream() async throws {
        try await coordinator.run(
            kind: .media
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Disconnect realtime before stopping the local " +
                    "video stream"
            )
            token.setFailureScope(.all)
            await mediaController.stopLocalVideoStream()
            try token.ensureCurrent()
            errorHandler.invalidatePendingFailures()
            let hasLocalMedia = await mediaController.currentTrack != nil
            try await coordinator.commit(
                RealtimeState(connectionState: hasLocalMedia ? .ready : .idle), token: token
            )
        }
    }

    func connect(
        localStream: RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        try await coordinator.run(
            kind: .connection
        ) { [self] token in
            try await performConnect(
                localStream: localStream,
                token: token
            )
        }
    }

    func disconnect() async {
        await coordinator.disconnect()
    }

    func disconnect(reason: RealtimeReason) async {
        await coordinator.disconnect(reason: reason)
    }

    func close() async {
        await coordinator.terminate(
            .all
        )
    }

    func startGeneration(context: RealtimeContext?) async throws {
        try await coordinator.run(
            kind: .generation
        ) { [self] token in
            let current = await coordinator.currentState
            try token.ensureCurrent()
            let measuresStartup = current.connectionState == .connected
            if measuresStartup {
                timing.begin()
            }
            do {
                try await performStartGeneration(
                    context: context,
                    token: token
                )
            } catch {
                if measuresStartup {
                    timing.finishFailure(error)
                }
                throw error
            }
        }
    }

    func startGeneration(
        localStream: RealtimeMediaStream,
        context: RealtimeContext?
    ) async throws -> RealtimeMediaStream {
        try await coordinator.run(
            kind: .generation
        ) { [self] token in
            let initialState = await coordinator.currentState
            let hasConnection = await connectionManager.currentSessionID != ""
            try token.ensureCurrent()
            let measuresStartup = initialState.connectionState != .connecting &&
                initialState.connectionState != .disconnecting
            if measuresStartup {
                timing.begin()
            }
            do {
                guard await mediaController.owns(localStream) else {
                    throw XmaxError(
                        code: .invalidConfiguration,
                        message: "The local stream must be created and " +
                            "started by this realtime manager"
                    )
                }
                try token.ensureCurrent()

                try await generationManager.validateContext(context)
                try token.ensureCurrent()
                let remoteStream: RealtimeMediaStream
                if hasConnection {
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
                }

                try await performStartGeneration(
                    context: context,
                    token: token
                )
                return remoteStream
            } catch {
                if measuresStartup {
                    timing.finishFailure(error)
                }
                throw error
            }
        }
    }

    private func performStartGeneration(
        context: RealtimeContext?,
        token: RealtimeCoordinator.Token
    ) async throws {
        try token.ensureCurrent()
        let sessionID = await connectionManager.currentSessionID
        let current = await coordinator.currentState
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
                targetSize: await connectionManager.currentTargetSize,
                context: context
            )
            try token.ensureCurrent()
            return
        }

        try await generationManager.validateContext(context)
        try token.ensureCurrent()
        token.setFailureScope(.connection)
        do {
            await mediaController.setLocalAudioPreviewMuted(true)
            let taskID = try await generationManager.start(
                videoFormat: videoFormat,
                targetSize: await connectionManager.currentTargetSize,
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
        guard await mediaController.owns(localStream) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "The local stream must be created and started " +
                    "by this realtime manager"
            )
        }

        try await mediaController.updateCameraOrientation()
        try token.ensureCurrent()
        guard let videoFormat = localStream.videoTrack?.videoFormat else {
            throw XmaxError(code: .invalidConfiguration, message: "Local video format is unavailable")
        }

        token.setFailureScope(.connection)
        try await generationManager.reset()
        try token.ensureCurrent()
        try await coordinator.commit(
            RealtimeState(connectionState: .connecting),
            token: token
        )
        try streamController.setVideoEncoderConfig(videoFormat)
        let targetSize = await reconcileFrameInterpolation(for: localStream)
        try token.ensureCurrent()
        try await mediaController.startMicrophoneCapture()
        try token.ensureCurrent()
        let remoteStream = try await connectionManager.connect(
            model: options.model,
            videoFormat: videoFormat,
            targetSize: targetSize,
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

    func createLocalMediaStream(
        source: RealtimeMediaSource,
        prepare: @escaping @Sendable (RealtimeCoordinator.Token) async throws
            -> RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        return try await coordinator.run(
            kind: .media
        ) { [self] token in
            try await ensureLocalMediaCanChange(
                message: "Local \(source.rawValue) stream is unavailable during " +
                    "a realtime connection"
            )
            guard await mediaController.currentTrack == nil else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Stop the current local media stream before creating another one"
                )
            }
            try token.ensureCurrent()
            errorHandler.invalidatePendingFailures()
            try await coordinator.commit(RealtimeState(connectionState: .preparing), token: token)
            try token.ensureCurrent()

            let stream = try await prepare(token)
            try token.ensureCurrent()
            token.setFailureScope(.all)
            if let track = stream.videoTrack {
                await MainActor.run {
                    track.orientationChangeHandler = { [weak self, weak track] changedAxis in
                        guard let track else { return }
                        Task { await self?.handleOrientationChange(for: track, changedAxis: changedAxis) }
                    }
                }
                try token.ensureCurrent()
            }
            await reconcileFrameInterpolation(for: stream)
            try token.ensureCurrent()
            try streamController.setRemoteAudioVolume(source == .video ? 1 : 0)
            if source == .camera {
                await mediaController.setCameraPreviewReadyHandler { [coordinator] isCurrent in
                    Task {
                        await coordinator.localPreviewDidBecomeReady(isCurrent: isCurrent)
                    }
                }
            } else {
                try await coordinator.commit(RealtimeState(connectionState: .ready), token: token)
            }
            return stream
        }
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

    func handleOrientationChange(for track: RealtimeVideoTrack, changedAxis: Bool) async {
        guard await mediaController.currentTrack === track else { return }
        let disconnection = changedAxis
            ? await coordinator.beginDisconnect(reason: .orientationChanged)
            : nil

        if await mediaController.currentTrack === track {
            do {
                try await mediaController.updateCameraOrientation()
            } catch {
                if await mediaController.currentTrack === track {
                    await coordinator.terminate(with: XmaxError.from(error), target: .all)
                }
            }
        }
        await disconnection?.value
    }

    @discardableResult
    func reconcileFrameInterpolation(
        for stream: RealtimeMediaStream
    ) async -> CGSize? {
        guard await renderController.isFrameInterpolationEnabled,
              let videoFormat = stream.videoTrack?.videoFormat else {
            return nil
        }
        do {
            let targetSize = try mediaService.resolveFrameInterpolationSize(videoFormat.size)
            guard mediaService.supportsFrameInterpolation(for: targetSize) else {
                throw XmaxError(
                    code: .frameInterpolationUnsupported,
                    message: "Frame interpolation is unavailable for " +
                        "\(Int(targetSize.width)) × \(Int(targetSize.height)) video",
                    severity: .recoverable
                )
            }
            try await renderController.setFrameInterpolationEnabled(
                true,
                videoFormat: videoFormat.resized(
                    width: Int(targetSize.width),
                    height: Int(targetSize.height)
                )
            )
            return targetSize == videoFormat.size ? nil : targetSize
        } catch {
            try? await renderController.setFrameInterpolationEnabled(
                false,
                videoFormat: videoFormat
            )
            await errorHandler.report(XmaxError.from(error).withSeverity(.recoverable))
            return nil
        }
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
        if scope == .all {
            await mediaController.setLocalAudioPreviewMuted(true)
        }

        do {
            try await mediaController.stopMicrophoneCapture()
        } catch {
            XmaxLogger.realtime.error(
                message: """
                停止麦克风采集失败 (Failed to Stop Microphone Capture)
                └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                """
            )
        }

        do {
            try await generationManager.reset(taskID: taskID)
        } catch {
            XmaxLogger.realtime.error(
                message: """
                停止实时生成失败 (Failed to Stop Realtime Generation)
                └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                """
            )
        }

        let activeSessionID = await connectionManager.currentSessionID
        var sessionID = activeSessionID.isEmpty ? nil : activeSessionID
        do {
            sessionID = try await connectionManager.disconnect() ?? sessionID
        } catch {
            XmaxLogger.realtime.error(
                message: """
                断开实时连接失败 (Failed to Disconnect Realtime)
                └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                """
            )
        }

        if scope == .all {
            await mediaController.stopLocalStream()
        } else {
            await mediaController.setLocalAudioPreviewMuted(false)
            do {
                try await mediaController.updateCameraOrientation()
            } catch {
                XmaxLogger.realtime.error(
                    message: """
                    更新摄像头方向失败 (Failed to Update Camera Orientation)
                    └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                    """
                )
            }
        }
        return RealtimeCoordinator.CleanupResult(
            sessionID: sessionID,
            hasLocalMedia: await mediaController.currentTrack != nil
        )
    }
}
