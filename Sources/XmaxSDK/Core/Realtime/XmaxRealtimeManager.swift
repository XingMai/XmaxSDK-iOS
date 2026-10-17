//
//  XmaxRealtimeManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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


    // 错误与耗时记录
    private let errorHandler: RealtimeErrorHandler
    private let timing: RealtimeTiming


    // 并发控制
    private let coordinator: RealtimeCoordinator


    // 自动调档
    private var qualityPending = false

    /// 创建实时生成组件，并连接媒体、传输、渲染和生命周期管理能力。
    ///
    /// - Parameters:
    ///   - options: 模型与初始插帧配置。
    ///   - apiService: 创建和关闭实时会话的 API 服务。
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

    /// 使用指定业务组件创建实时生成管理器。
    ///
    /// - Parameters:
    ///   - options: 模型与初始插帧配置。
    ///   - streamController: 管理 RTC 传输、信令和网络质量的组件。
    ///   - mediaController: 管理本地媒体和轨迹交互的组件。
    ///   - renderController: 管理视频轨道显示和插帧的组件。
    ///   - mediaService: 提供模型尺寸和插帧能力规则的服务。
    ///   - connectionManager: 管理服务端会话和远端媒体资源的组件。
    ///   - errorHandler: 记录错误并转交生命周期故障的组件。
    ///   - generationManager: 管理生成任务与条件更新的组件。
    ///   - timing: 记录本次实时启动各阶段耗时的组件。
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


    // 生命周期状态
    /// 当前实时连接与生成状态。
    var currentState: RealtimeState {
        get async {
            await coordinator.currentState
        }
    }


    // 渲染状态
    /// 当前实际生效的远端插帧状态。
    var isFrameInterpolationEnabled: Bool {
        get async {
            await renderController.isFrameInterpolationEnabled
        }
    }


    // 音频状态
    /// 当前本地预览音量，范围为 `0...1`。
    var localAudioVolume: Float {
        get async {
            await mediaController.localAudioVolume
        }
    }

    /// 当前远端生成音频的播放音量，范围为 `0...1`。
    var remoteAudioVolume: Float {
        streamController.remoteAudioVolume
    }


    // 传输状态
    /// 当前生成任务的传输配置快照；未生成或规格不可用时为空。
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

    /// 应用指定方向的传输档位，后续继续按网络质量自动调整。
    ///
    /// - Parameters:
    ///   - level: 目标档位，取值范围为 1...5。
    ///   - downlink: true 调整下行，false 调整上行。
    /// - Throws: 档位无效、未处于生成状态、操作冲突、取消或配置失败时抛出错误。
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

    /// 设置实时状态监听器。
    ///
    /// - Parameter listener: 实时状态回调；传入 `nil` 时清除监听器。
    func setStateListener(_ listener: RealtimeStateListener?) async {
        await coordinator.setStateListener(listener)
    }

    /// 设置远端最终视频帧监听器。
    ///
    /// 监听器接收完成可选插帧处理、即将用于画面显示的视频帧。回调由 SDK
    /// 内部串行队列触发，不会阻塞主线程；调用方应快速转交帧数据，避免在
    /// 回调中执行耗时编码。传入 `nil` 时清除监听器。
    ///
    /// - Parameter listener: 远端最终视频帧回调。
    func setRemoteVideoFrameListener(
        _ listener: RealtimeVideoFrameListener?
    ) async {
        await renderController.setRemoteVideoFrameListener(listener)
    }

    /// 设置视频上行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；未发布或断开连接时收到 nil；传入 nil 清除监听器。
    func setUplinkVideoStatisticsListener(_ listener: UplinkVideoStatisticsListener?) {
        streamController.setUplinkVideoStatisticsListener(listener)
    }

    /// 设置视频下行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；结果流清理时收到 nil；传入 nil 清除监听器。
    func setDownlinkVideoStatisticsListener(_ listener: DownlinkVideoStatisticsListener?) {
        streamController.setDownlinkVideoStatisticsListener(listener)
    }

    /// 设置网络质量监听器。
    ///
    /// - Parameter listener: 上下行网络质量回调；传入 `nil` 时清除监听器。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) {
        streamController.setNetworkQualityListener(listener)
    }

    /// 设置设备性能告警监听器。
    ///
    /// - Parameter listener: 设备性能告警回调；传入 `nil` 时清除监听器。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) {
        streamController.setPerformanceAlarmListener(listener)
    }

    /// 设置本地媒体预览音量。
    ///
    /// - Parameter volume: 本地预览音量，取值范围为 `0...1`。
    /// - Throws: 音量超出有效范围时抛出错误。
    func setLocalAudioVolume(_ volume: Float) async throws {
        do {
            try Self.validateAudioVolume(volume)
            await mediaController.setLocalAudioVolume(volume)
        } catch {
            throw await reportError(error)
        }
    }

    /// 设置远端生成音频播放音量。
    ///
    /// 尚未连接或订阅远端流时保存配置，并在远端音频开始播放前应用。
    /// 如需覆盖初始音量，请在创建本地流后调用。
    ///
    /// - Parameter volume: 远端播放音量，取值范围为 `0...1`。
    /// - Throws: 音量超出有效范围或 RTC 音量配置失败时抛出错误。
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

    /// 开启或关闭远端生成画面的插帧。
    ///
    /// 设置结果覆盖初始化配置。生成中开启时请求等比例缩小回传尺寸，关闭时
    /// 请求恢复当前网络档位的回传尺寸；不会重新连接或重启生成。
    /// 尺寸切换期间继续显示原始帧。
    ///
    /// - Parameter enabled: 是否开启远端视频插帧。
    /// - Throws: 其他实时操作正在执行、设备或目标尺寸不支持插帧，或信令发送失败时抛出错误。
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

    /// 创建本地相机流并开始预览。
    ///
    /// 将返回的轨道绑定到预览视图；收到有效帧且视图已绑定后进入 `ready`。
    ///
    /// - Parameters:
    ///   - videoFormat: 相机采集的视频规格。
    ///   - position: 首次启用的摄像头位置。
    ///   - useMicrophone: 是否使用麦克风；创建时申请权限，连接时开始采集，断开时停止采集。
    /// - Returns: 包含本地相机视频轨道的媒体流。
    /// - Throws: 配置无效、所需权限被拒绝、操作冲突或采集启动失败时抛出错误。
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

    /// 停止本地相机流并更新媒体就绪状态。
    ///
    /// - Throws: 尚未断开实时连接、存在冲突操作或当前操作被取消时抛出错误。
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

    /// 切换前后置摄像头。
    ///
    /// 生成过程中调用时，SDK 会停止当前生成、切换摄像头，并使用缓存的生成
    /// 条件恢复生成；RTC 连接保持不变。连接或生成正在启动时不可切换。
    ///
    /// - Returns: 复用原视频轨道并更新摄像头位置后的本地媒体流。
    /// - Throws: 当前没有摄像头流、实时流程正在启动，或摄像头切换及生成恢复
    ///   失败时抛出错误。
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

    /// 从编码后的图片数据创建持续输出帧的媒体流。
    ///
    /// 保留媒体显示比例；生成时由模型规则选择生成画布。
    ///
    /// - Parameter imageData: JPEG、PNG 等受支持格式的编码图片数据。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 配置无效、操作冲突或图片处理失败时抛出错误。
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
    /// 保留媒体显示比例；生成时由模型规则选择生成画布。
    ///
    /// - Parameter image: 用作本地输入的 UIKit 图片。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 配置无效、操作冲突或图片处理失败时抛出错误。
    func createLocalImageStream(
        image: UIImage
    ) async throws -> RealtimeMediaStream {
        let decodedImage = try ImageManager().decode(image)
        return try await createLocalImageStream(
            decodedImage: decodedImage
        )
    }
#endif

    /// 从已解码图片创建持续输出帧的本地媒体流。
    ///
    /// - Parameter decodedImage: 已完成解码和方向处理的图片。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 本地媒体不可切换、操作取消或图片流创建失败时抛出错误。
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

    /// 从本地图片文件创建持续输出帧的媒体流。
    ///
    /// 保留媒体显示比例；生成时由模型规则选择生成画布。
    ///
    /// - Parameter fileURL: 本地图片文件 URL。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 配置无效、操作冲突或图片处理失败时抛出错误。
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

    /// 停止本地图片流并更新媒体就绪状态。
    ///
    /// - Throws: 尚未断开实时连接、存在冲突操作或当前操作被取消时抛出错误。
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

    /// 从本地视频文件创建循环播放的音视频流。
    ///
    /// 保留源视频显示比例，使用模型默认输出帧率；生成时单独计算生成画布。
    ///
    /// - Parameter fileURL: 本地视频文件 URL。
    /// - Returns: 包含本地文件视频轨道的媒体流。
    /// - Throws: 配置无效、操作冲突或视频处理失败时抛出错误。
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

    /// 停止本地文件视频流并更新媒体就绪状态。
    ///
    /// - Throws: 尚未断开实时连接、存在冲突操作或当前操作被取消时抛出错误。
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

    /// 使用当前 Manager 创建的本地流建立实时连接。
    ///
    /// - Parameter localStream: 当前 Manager 创建并持有的本地媒体流。
    /// - Returns: 当前连接的远端媒体流，可绑定到结果预览视图。
    /// - Throws: 本地流无效、连接已存在、操作冲突、取消或连接建立失败时抛出错误。
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

    /// 断开实时连接并保留当前本地媒体预览。
    func disconnect() async {
        await coordinator.disconnect()
    }

    /// 按指定业务原因断开实时连接，保留可用的本地媒体流。
    ///
    /// - Parameter reason: 本次断开的原因，例如显示方向变化。
    func disconnect(reason: RealtimeReason) async {
        await coordinator.disconnect(reason: reason)
    }

    /// 关闭当前实时生命周期并释放连接、本地媒体和 RTC Engine。
    ///
    /// 关闭期间重复调用会等待同一个释放任务；关闭完成后仍可重新创建本地流。
    func close() async {
        await coordinator.terminate(
            .all
        )
    }

    /// 开始生成，生成中再次调用时更新当前条件。
    ///
    /// - Parameters:
    ///   - context: 本次生成条件；首次生成不能为空，后续传入 `nil` 时复用缓存条件。
    ///   - faceRestoration: 是否回贴原始人脸；每次调用均发送本次设置。
    /// - Throws: 条件无效或生成启动、更新失败时抛出错误。
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

    /// 使用当前本地流按需建立连接并开始生成。
    ///
    /// 文件视频在连接和生成期间保持本地播放器持续运行；已经连接时直接复用
    /// 当前连接。返回的远端流可交给统一视频视图显示生成结果。
    ///
    /// - Parameters:
    ///   - localStream: 当前 Manager 创建并持有的本地媒体流。
    ///   - context: 本次生成条件；首次生成不能为空。
    ///   - faceRestoration: 是否回贴原始人脸；每次调用均发送本次设置。
    /// - Returns: 当前 RTC 连接对应的远端媒体流。
    /// - Throws: 本地流无效、连接失败或生成启动失败时抛出错误。
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

    /// 启动结果流并提交生成状态，或更新现有生成任务的条件。
    ///
    /// - Parameters:
    ///   - context: 本次生成条件；nil 时复用上次成功请求的条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - token: 当前操作凭证，用于校验生命周期仍然有效。
    /// - Throws: 连接不可用、条件无效、操作取消或生成启动及更新失败时抛出错误。
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
    /// 根据网络档位和插帧限制计算回传视频规格。
    ///
    /// - Parameters:
    ///   - baseline: 本地媒体的基准规格。
    ///   - level: 下行目标档位，取值范围为 1...5。
    ///   - interpolation: 是否应用插帧所需的像素面积限制。
    /// - Returns: 保持媒体比例并满足当前传输限制的回传规格。
    /// - Throws: 无法计算有效的插帧尺寸时抛出错误。
    nonisolated func resolveReturnFormat(
        baseline: RealtimeVideoFormat,
        level: Int,
        interpolation: Bool
    ) throws -> RealtimeVideoFormat {
        let limit = interpolation ? try mediaService.resolveFrameInterpolationSize(baseline.size) : nil
        return QualityVideoFormat.resolveReturnFormat(baseline, level: level, interpolationSize: limit)
    }

    /// 根据当前任务的网络采样尝试自动调档，忙碌时跳过本次采样。
    ///
    /// - Parameters:
    ///   - sample: 上下行网络质量采样。
    ///   - sampledAt: 采样时的系统单调时钟时间，单位为秒。
    ///   - taskID: 采样所属的生成任务标识。
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

    /// 应用单个方向的传输配置，并在成功后保存当前档位。
    ///
    /// - Parameters:
    ///   - level: 目标档位，取值范围为 1...5。
    ///   - downlink: true 更新回传尺寸，false 更新本地编码规格。
    ///   - taskID: 需要更新传输配置的生成任务标识。
    ///   - token: 当前配置操作的生命周期凭证。
    /// - Throws: 操作取消、目标尺寸不支持插帧、信令发送或编码配置失败时抛出错误。
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

    /// 发布本地媒体并建立实时会话，成功后提交已连接状态。
    ///
    /// - Parameters:
    ///   - localStream: 当前管理器创建并持有的本地媒体流。
    ///   - token: 当前连接操作的生命周期凭证。
    /// - Returns: 当前会话对应的远端媒体流。
    /// - Throws: 连接已存在、本地流无效、操作取消或会话及 RTC 连接失败时抛出错误。
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

    /// 创建本地媒体流，配置方向处理、初始音量和媒体就绪通知。
    ///
    /// - Parameters:
    ///   - source: 本次创建的媒体来源。
    ///   - prepare: 创建媒体流的异步操作，接收当前生命周期凭证。
    /// - Returns: 完成媒体准备的本地流；摄像头就绪状态由首帧预览通知更新。
    /// - Throws: 已有本地流、实时连接未断开、操作取消或媒体准备失败时抛出错误。
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

    /// 确认当前没有阻止本地媒体变更的实时连接。
    ///
    /// - Parameter message: 不允许变更媒体时使用的错误信息。
    /// - Throws: 存在会话，或连接正在建立、断开时抛出错误。
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

    /// 更新当前媒体方向，横竖屏轴变化时结束实时连接。
    ///
    /// - Parameters:
    ///   - track: 报告方向变化的本地视频轨道。
    ///   - changedAxis: 是否在横屏和竖屏之间切换。
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

    /// 为本地流配置有效的回传尺寸；不支持插帧时关闭插帧并保留媒体流程。
    ///
    /// - Parameter stream: 当前本地媒体流。
    /// - Returns: 结合网络档位和插帧限制计算的回传尺寸；没有视频规格时返回 nil。
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

    /// 结束心跳失败的当前会话，忽略已结束会话的迟到通知。
    ///
    /// - Parameters:
    ///   - sessionID: 发生心跳故障的会话标识。
    ///   - error: 心跳请求返回的错误。
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

    /// 记录错误并转换为统一的 SDK 错误类型。
    ///
    /// - Parameter error: 需要记录和转换的原始错误。
    /// - Returns: 供调用方抛出或处理的 XmaxError。
    @discardableResult
    func reportError(_ error: any Error) async -> XmaxError {
        let xmaxError = XmaxError.from(error)
        await errorHandler.report(xmaxError)
        return xmaxError
    }

    /// 确认音量是 0...1 范围内的有限数值。
    ///
    /// - Parameter volume: 待应用的播放音量。
    /// - Throws: 音量非有限数值或超出范围时抛出错误。
    static func validateAudioVolume(_ volume: Float) throws {
        guard volume.isFinite, (0...1).contains(volume) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Audio volume must be between 0 and 1"
            )
        }
    }

    /// 释放指定范围内的实时资源，并返回清理后的会话和本地媒体信息。
    ///
    /// - Parameters:
    ///   - scope: 需要释放的资源范围。
    ///   - taskID: 需要停止的生成任务标识；空字符串表示没有指定任务。
    ///   - mediaController: 负责停止采集或恢复本地预览的媒体组件。
    ///   - connectionManager: 负责释放 RTC 房间和服务端会话的组件。
    ///   - generationManager: 负责停止生成并清理缓存条件的组件。
    /// - Returns: 已结束的会话标识和本地媒体是否仍然可用。
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
