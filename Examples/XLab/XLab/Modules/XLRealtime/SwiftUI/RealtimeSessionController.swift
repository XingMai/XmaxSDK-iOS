import Combine
import Foundation
import XmaxSDK

@MainActor
final class RealtimeSessionController: ObservableObject {

    // 视频轨道
    @Published private(set) var localVideoTrack: RealtimeVideoTrack?
    @Published private(set) var remoteVideoTrack: RealtimeVideoTrack?

    // 实时状态
    @Published private(set) var connectionState: RealtimeConnectionState = .idle
    @Published private(set) var isGenerationRequested = false
    @Published private(set) var isLoading = true

    // 设备状态
    @Published private(set) var isBackCameraSelected = false
    @Published private(set) var isCameraSwitching = false
    @Published private(set) var isFrameInterpolationEnabled: Bool

    // 错误状态
    @Published private(set) var errorMessage: String?

    // SDK 资源
    private let realtimeManager: any XmaxRealtimeManaging
    private var localMediaStream: RealtimeMediaStream?

    // 生命周期状态
    private var hasStarted = false

    // 异步任务
    private var startupTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var cameraSwitchTask: Task<Void, Never>?
    private var frameInterpolationTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

    var isMediaReady: Bool {
        switch connectionState {
        case .ready, .connecting, .connected, .generating:
            true
        case .disconnecting:
            localMediaStream != nil
        case .idle, .preparing:
            false
        }
    }

    init() {
        let initialFrameInterpolationEnabled: Bool
        if #available(iOS 26.0, *) {
            initialFrameInterpolationEnabled = true
        } else {
            initialFrameInterpolationEnabled = false
        }
        isFrameInterpolationEnabled = initialFrameInterpolationEnabled

        let apiKey = UserDefaults.standard.string(
            forKey: RealtimePreferences.apiKeyStorageKey
        ) ?? ""
        let client = XmaxClient(
            configuration: XmaxConfiguration(
                apiKey: apiKey,
                environment: RealtimePreferences.environment,
                loggerOptions: [.business, .performance]
            )
        )
        realtimeManager = client.createRealtimeManager(
            options: RealtimeConfiguration(
                model: RealtimePreferences.selectedModel,
                isFrameInterpolationEnabled: initialFrameInterpolationEnabled
            )
        )
    }

    deinit {
        startupTask?.cancel()
        generationTask?.cancel()
        cameraSwitchTask?.cancel()
        frameInterpolationTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let pendingCleanup = cleanupTask
        cleanupTask = nil
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            await pendingCleanup?.value
            guard let self, hasStarted, !Task.isCancelled else { return }

            await realtimeManager.setStateListener { [weak self] state in
                self?.renderRealtimeState(state)
            }
            do {
                let stream = try await realtimeManager.createLocalCameraStream(
                    videoFormat: RealtimePreferences.cameraVideoFormat,
                    position: .front,
                    useMicrophone: true
                )
                guard hasStarted, !Task.isCancelled else { return }
                localMediaStream = stream
                localVideoTrack = stream.videoTrack
                isFrameInterpolationEnabled =
                    await realtimeManager.isFrameInterpolationEnabled
            } catch {
                guard hasStarted, !Task.isCancelled else { return }
                handleRealtimeError(XmaxError.from(error))
            }
        }
    }

    func startGeneration(context: RealtimeContext) {
        guard let localMediaStream else {
            errorMessage = XLLocalization.text("realtime.media.notReady")
            return
        }

        isGenerationRequested = true
        isLoading = true

        let previousTask = generationTask
        previousTask?.cancel()
        generationTask = Task { [weak self] in
            await previousTask?.value
            guard let self, !Task.isCancelled else { return }

            do {
                let remoteStream = try await realtimeManager.startGeneration(
                    localStream: localMediaStream,
                    context: context
                )
                guard !Task.isCancelled else {
                    await realtimeManager.disconnect()
                    return
                }
                remoteVideoTrack = remoteStream.videoTrack
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if await realtimeManager.currentState.connectionState != .generating {
                    isGenerationRequested = false
                    remoteVideoTrack = nil
                }
                isLoading = false
                handleRealtimeError(XmaxError.from(error))
            }
        }
    }

    func disconnectGeneration() {
        guard isGenerationRequested || remoteVideoTrack != nil else { return }

        isGenerationRequested = false
        remoteVideoTrack = nil
        isLoading = connectionState == .preparing

        let previousTask = generationTask
        previousTask?.cancel()
        generationTask = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            // 新的生成请求会等待本任务；即使被取消，也必须完成旧连接清理。
            await realtimeManager.disconnect()
            remoteVideoTrack = nil
        }
    }

    func switchCamera() {
        guard localMediaStream != nil, !isCameraSwitching else { return }

        isCameraSwitching = true
        let retainedRemoteVideoTrack = remoteVideoTrack
        if isGenerationRequested {
            remoteVideoTrack = nil
            isLoading = true
        }
        cameraSwitchTask?.cancel()
        cameraSwitchTask = Task { [weak self] in
            guard let self else { return }
            defer { isCameraSwitching = false }
            do {
                let stream = try await realtimeManager.switchCamera()
                guard !Task.isCancelled else { return }
                localMediaStream = stream
                localVideoTrack = stream.videoTrack
                isBackCameraSelected.toggle()
                if isGenerationRequested {
                    remoteVideoTrack = retainedRemoteVideoTrack
                    isLoading = false
                } else {
                    isLoading = connectionState == .preparing
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if !isGenerationRequested {
                    isLoading = connectionState == .preparing
                }
                handleRealtimeError(XmaxError.from(error))
            }
        }
    }

    func setFrameInterpolationEnabled(_ enabled: Bool) {
        frameInterpolationTask?.cancel()
        frameInterpolationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await realtimeManager.setFrameInterpolationEnabled(enabled)
            } catch {
                guard !Task.isCancelled else { return }
                let resolvedError = XmaxError.from(error)
                if resolvedError.code != .cancelled {
                    errorMessage = resolvedError.localizedDescription
                }
            }
            guard !Task.isCancelled else { return }
            isFrameInterpolationEnabled =
                await realtimeManager.isFrameInterpolationEnabled
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func close() {
        guard hasStarted else { return }
        hasStarted = false

        let pendingStartup = startupTask
        let pendingGeneration = generationTask
        let pendingCameraSwitch = cameraSwitchTask
        let pendingFrameInterpolation = frameInterpolationTask
        startupTask?.cancel()
        startupTask = nil
        generationTask?.cancel()
        generationTask = nil
        cameraSwitchTask?.cancel()
        cameraSwitchTask = nil
        frameInterpolationTask?.cancel()
        frameInterpolationTask = nil

        localMediaStream = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        connectionState = .idle
        isGenerationRequested = false
        isLoading = false
        isBackCameraSelected = false
        isCameraSwitching = false

        let realtimeManager = realtimeManager
        cleanupTask = Task {
            await pendingStartup?.value
            await pendingGeneration?.value
            await pendingCameraSwitch?.value
            await pendingFrameInterpolation?.value
            await realtimeManager.setStateListener(nil)
            await realtimeManager.close()
        }
    }

    private func renderRealtimeState(_ state: RealtimeState) {
        connectionState = state.connectionState
        if let reason = state.reason, reason != .normal {
            isGenerationRequested = false
        }
        if state.connectionState == .idle {
            localMediaStream = nil
            localVideoTrack = nil
        }
        switch state.connectionState {
        case .preparing:
            isLoading = true
        case .connecting, .connected:
            if isGenerationRequested {
                remoteVideoTrack = nil
                isLoading = true
            }
        case .generating:
            guard isGenerationRequested else { return }
            if remoteVideoTrack != nil {
                isLoading = false
            }
        case .idle, .ready, .disconnecting:
            if !isGenerationRequested {
                remoteVideoTrack = nil
                isLoading = false
            }
        }
        if state.connectionState == .idle { isLoading = false }
        if case .failure(let error) = state.reason {
            handleRealtimeError(error)
        }
    }

    private func handleRealtimeError(_ error: XmaxError) {
        guard error.code != .cancelled else { return }
        errorMessage = error.localizedDescription
    }
}
