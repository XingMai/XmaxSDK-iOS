import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 实时生成业务公共入口，统一编排本地媒体、连接、生成和状态通知。
actor XmaxRealtimeManager: XmaxRealtimeManaging, RealtimeQualityDebugging {

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

    // 自动调档
    private var qualityPending = false

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
            await coordinator?.terminate(
                with: error,
                target: target,
                isCurrent: isCurrent
            )
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

    var qualityDebugState: RealtimeQualityDebugState? {
        get async {
            guard await coordinator.currentState.connectionState == .generating,
                  let quality = streamController.qualityConfiguration else { return nil }
            let interpolation = await renderController.isFrameInterpolationEnabled
            guard let downlink = try? resolveReturnFormat(baseline: quality.baseline, level: quality.downlinkLevel, interpolation: interpolation),
                  await coordinator.currentState.connectionState == .generating else { return nil }
            return RealtimeQualityDebugState(
                uplinkLevel: quality.uplinkLevel, downlinkLevel: quality.downlinkLevel,
                uplink: quality.uplink, downlink: downlink, interpolationEnabled: interpolation
            )
        }
    }

    func selectQualityLevel(_ level: Int, downlink: Bool) async throws {
        guard (1...5).contains(level) else {
            throw XmaxError(code: .invalidConfiguration, message: "Quality level must be in 1...5")
        }
        try await coordinator.run(kind: .configuration) { [self] token in
            let state = await coordinator.currentState
            try token.ensureCurrent()
            guard state.connectionState == .generating, let taskID = state.taskID else {
                throw XmaxError(code: .invalidConfiguration, message: "Quality selection requires active generation")
            }
            try await applyQualityLevel(level, downlink: downlink, taskID: taskID, token: token)
        }
    }

    func setStateListener(_ listener: RealtimeStateListener?) async {
        await coordinator.setStateListener(listener)
    }

    func setRemoteVideoFrameListener(
        _ listener: RealtimeVideoFrameListener?
    ) async {
        await renderController.setRemoteVideoFrameListener(listener)
    }

    func setUplinkVideoStatisticsListener(_ listener: UplinkVideoStatisticsListener?) {
        streamController.setUplinkVideoStatisticsListener(listener)
    }

    func setDownlinkVideoStatisticsListener(_ listener: DownlinkVideoStatisticsListener?) {
        streamController.setDownlinkVideoStatisticsListener(listener)
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
                XmaxError.from(error)
            )
        }
    }

    func setFrameInterpolationEnabled(_ enabled: Bool) async throws {
        try await coordinator.run(
            kind: .configuration
        ) { [self] token in
            do {
                let current = await coordinator.currentState
                let mediaFormat = await mediaController.currentVideoFormat
                let targetSize = try mediaFormat.map {
                    try resolveReturnFormat(
                        baseline: $0,
                        level: streamController.qualityConfiguration?.downlinkLevel ?? 2,
                        interpolation: enabled
                    ).size
                }
                if enabled, let targetSize,
                   !mediaService.supportsFrameInterpolation(for: targetSize) {
                    throw XmaxError(
                        code: .frameInterpolationUnsupported,
                        message: "Frame interpolation is unavailable for " +
                            "\(Int(targetSize.width)) × \(Int(targetSize.height)) video"
                    )
                }
                try token.ensureCurrent()
                if let taskID = current.taskID, let targetSize,
                   await connectionManager.currentTargetSize != targetSize {
                    try await streamController.changeTargetSize(
                        taskID: taskID,
                        targetSize: targetSize,
                        ensureActive: { try token.ensureCurrent() }
                    )
                }

                // 信令发出后完成本地配置提交；并发断开会等待当前操作完成再清理。
                if let mediaFormat, let targetSize {
                    await connectionManager.updateTargetSize(targetSize, videoFormat: mediaFormat)
                }
                var returnFormat = mediaFormat
                if let mediaFormat, let targetSize {
                    returnFormat = mediaFormat.resized(
                        width: Int(targetSize.width),
                        height: Int(targetSize.height)
                    )
                }
                try await renderController.setFrameInterpolationEnabled(
                    enabled,
                    videoFormat: returnFormat
                )
            } catch {
                throw XmaxError.from(error)
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
                    faceRestoration: await generationManager.cachedFaceRestoration,
                    token: token
                )
            }
            return stream
        }
    }

    func createLocalImageStream(
        imageData: Data
    ) async throws -> RealtimeMediaStream {
        try await createLocalMediaStream(source: .image) { [self] token in
            let stream = try await mediaController.createLocalImageStream(
                imageData: imageData
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
    func createLocalImageStream(
        image: UIImage
    ) async throws -> RealtimeMediaStream {
        let decodedImage = try ImageManager().decode(image)
        return try await createLocalImageStream(
            decodedImage: decodedImage
        )
    }
#endif

    func createLocalImageStream(
        decodedImage: any DecodedImage
    ) async throws -> RealtimeMediaStream {
        try await createLocalMediaStream(source: .image) { [self] token in
            let stream = try await mediaController.createLocalImageStream(
                decodedImage: decodedImage
            )
            try token.ensureCurrent()
            return stream
        }
    }

    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createLocalMediaStream(source: .image) { [self] token in
            let stream = try await mediaController.createLocalImageStream(
                fileURL: fileURL
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
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createLocalMediaStream(source: .video) { [self] token in
            let stream = try await mediaController.createLocalVideoStream(
                fileURL: fileURL
            )
            try token.ensureCurrent()
            return stream
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

    func startGeneration(context: RealtimeContext?, faceRestoration: Bool = false) async throws {
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
                    faceRestoration: faceRestoration,
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
        context: RealtimeContext?,
        faceRestoration: Bool = false
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
                    faceRestoration: faceRestoration,
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
        faceRestoration: Bool,
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
                message: "Realtime connection is not open"
            )
        }

        let paddingContain = await mediaController.usesContainPadding
        let generationSize = try paddingContain ? mediaService.resolveGenerationSize(videoFormat.size) : videoFormat.size
        let generationFormat = videoFormat.resized(width: Int(generationSize.width), height: Int(generationSize.height))
        try token.ensureCurrent()

        if current.connectionState == .generating,
           let taskID = current.taskID {
            try await generationManager.update(
                taskID: taskID,
                videoFormat: videoFormat,
                targetSize: nil,
                context: context,
                faceRestoration: faceRestoration,
                generationVideoFormat: generationFormat,
                paddingContain: paddingContain,
                ensureCurrent: { try token.ensureCurrent() }
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
                faceRestoration: faceRestoration,
                generationVideoFormat: generationFormat,
                paddingContain: paddingContain,
                ensureCurrent: {
                    try token.ensureCurrent()
                }
            )
            try await renderController.waitUntilRemoteFrameReady()
            try token.ensureCurrent()
            timing.finishFirstFrame(taskID: taskID)
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
            try token.ensureCurrent()
            if let quality = streamController.qualityConfiguration {
                streamController.completeQuality(downlink: false, level: quality.uplinkLevel, success: true)
                streamController.completeQuality(downlink: true, level: quality.downlinkLevel, success: true)
            }
            streamController.setAdaptiveQualityListener { [weak self] quality, time in
                Task { await self?.adaptQuality(quality, sampledAt: time, taskID: taskID) }
            }
            timing.finish(taskID: taskID)
        } catch {
            await mediaController.setLocalAudioPreviewMuted(false)
            throw error
        }
    }
}

private extension XmaxRealtimeManager {
    nonisolated func resolveReturnFormat(
        baseline: RealtimeVideoFormat,
        level: Int,
        interpolation: Bool
    ) throws -> RealtimeVideoFormat {
        let limit = interpolation ? try mediaService.resolveFrameInterpolationSize(baseline.size) : nil
        return QualityVideoFormat.resolveReturnFormat(baseline, level: level, interpolationSize: limit)
    }

    func adaptQuality(_ sample: RealtimeNetworkQuality, sampledAt: TimeInterval, taskID: String) async {
        guard !qualityPending else { return }
        qualityPending = true
        defer { qualityPending = false }
        do {
            let accepted = try await coordinator.runAdaptiveConfiguration { [self] token in
                let state = await coordinator.currentState
                try token.ensureCurrent()
                guard state.taskID == taskID, state.connectionState == .generating else { return }
                let change = streamController.proposeQuality(sample, sampledAt: sampledAt)
                if let level = change.uplink {
                    try? await applyQualityLevel(level, downlink: false, taskID: taskID, token: token)
                }
                try token.ensureCurrent()
                if let level = change.downlink {
                    try? await applyQualityLevel(level, downlink: true, taskID: taskID, token: token)
                }
            }
            if !accepted { streamController.resetQualitySamples() }
        } catch {
            // 取消与断开不形成新连接的采样，也不覆盖其配置。
            if !Task.isCancelled, await coordinator.currentState.taskID == taskID {
                streamController.resetQualitySamples()
            }
        }
    }

    func applyQualityLevel(
        _ level: Int,
        downlink: Bool,
        taskID: String,
        token: RealtimeCoordinator.Token
    ) async throws {
        guard let configuration = streamController.qualityConfiguration else { return }
        do {
            try token.ensureCurrent()
            let format: RealtimeVideoFormat
            if downlink {
                let interpolation = await renderController.isFrameInterpolationEnabled
                try token.ensureCurrent()
                format = try resolveReturnFormat(
                    baseline: configuration.baseline,
                    level: level,
                    interpolation: interpolation
                )
                guard !interpolation || mediaService.supportsFrameInterpolation(for: format.size) else {
                    throw XmaxError(
                        code: .frameInterpolationUnsupported,
                        message: "Frame interpolation is unavailable for the target size"
                    )
                }

                if await connectionManager.currentTargetSize != format.size {
                    try token.ensureCurrent()
                    try await streamController.changeTargetSize(
                        taskID: taskID,
                        targetSize: format.size,
                        ensureActive: { try token.ensureCurrent() }
                    )
                    // 发送后同步预期尺寸；断开会等待本次提交完成再释放资源。
                    await connectionManager.updateTargetSize(format.size, videoFormat: configuration.baseline)
                    try await renderController.setFrameInterpolationEnabled(interpolation, videoFormat: format)
                }
            } else {
                format = QualityVideoFormat.resolve(configuration.baseline, level: level, downlink: false)
                try streamController.setVideoEncoderConfig(format)
            }
            try token.ensureCurrent()
            streamController.completeQuality(downlink: downlink, level: level, success: true)
            XmaxLogger.realtime.debug(
                message: "自动调档 (Adaptive Quality)\n" +
                    "└─ \(downlink ? "Downlink" : "Uplink"): L\(level), \(format.width) × \(format.height)"
            )
        } catch {
            guard token.isCurrent else { throw error }
            streamController.completeQuality(downlink: downlink, level: level, success: false)
            XmaxLogger.realtime.warn(message: "自动调档失败 (Adaptive Quality Failed)\n└─ \(ErrorMessageFormatter.format(error))")
            throw error
        }
    }

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
        let quality = streamController.prepareQuality(baseline: videoFormat, model: options.model.rawValue)
        try streamController.setVideoEncoderConfig(quality.uplink)
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
        guard let videoFormat = stream.videoTrack?.videoFormat else {
            return nil
        }
        let level = streamController.qualityConfiguration?.downlinkLevel ?? 2
        let interpolation = await renderController.isFrameInterpolationEnabled
        do {
            let targetSize = try resolveReturnFormat(baseline: videoFormat, level: level, interpolation: interpolation).size
            guard !interpolation || mediaService.supportsFrameInterpolation(for: targetSize) else {
                throw XmaxError(
                    code: .frameInterpolationUnsupported,
                    message: "Frame interpolation is unavailable for " +
                        "\(Int(targetSize.width)) × \(Int(targetSize.height)) video"
                )
            }
            try await renderController.setFrameInterpolationEnabled(
                interpolation,
                videoFormat: videoFormat.resized(
                    width: Int(targetSize.width),
                    height: Int(targetSize.height)
                )
            )
            return targetSize
        } catch {
            try? await renderController.setFrameInterpolationEnabled(
                false,
                videoFormat: videoFormat
            )
            await errorHandler.report(XmaxError.from(error))
            return QualityVideoFormat.resolve(videoFormat, level: level, downlink: true).size
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
