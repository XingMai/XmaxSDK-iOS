import Combine
import Foundation
import XmaxSDK

@MainActor
final class RealtimeSessionController: ObservableObject {

    // 视频轨道
    @Published private(set) var localVideoTrack: RealtimeVideoTrack?
    @Published private(set) var remoteVideoTrack: RealtimeVideoTrack?

    // 实时状态
    @Published private(set) var isPreviewReady = false
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

    init() {
        let initialFrameInterpolationEnabled: Bool
        if #available(iOS 26.0, *) {
            initialFrameInterpolationEnabled = true
        } else {
            initialFrameInterpolationEnabled = false
        }
        isFrameInterpolationEnabled = initialFrameInterpolationEnabled

        let apiKey = UserDefaults.standard.string(
            forKey: RealtimeConst.apiKeyStorageKey
        ) ?? ""
        let client = XmaxClient(
            configuration: XmaxConfiguration(
                apiKey: apiKey,
                loggerOptions: .business
            )
        )
        realtimeManager = client.createRealtimeManager(
            options: RealtimeConfiguration(
                model: .x2_0,
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
        isLoading = true

        let pendingCleanup = cleanupTask
        cleanupTask = nil
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            await pendingCleanup?.value
            guard let self, hasStarted, !Task.isCancelled else { return }

            await realtimeManager.setErrorListener { [weak self] error in
                self?.handleRealtimeError(error)
            }
            await realtimeManager.setStateListener { [weak self] state in
                self?.renderRealtimeState(state)
            }
            await realtimeManager.setCameraPreviewReadyListener {
                [weak self] in
                self?.isPreviewReady = true
                self?.isLoading = false
            }

            do {
                let stream = try await realtimeManager.createLocalCameraStream(
                    videoFormat: RealtimeConst.cameraVideoFormat,
                    position: .front
                )
                guard hasStarted, !Task.isCancelled else { return }
                localMediaStream = stream
                localVideoTrack = stream.videoTrack
                isFrameInterpolationEnabled =
                    await realtimeManager.isFrameInterpolationEnabled
            } catch {
                guard hasStarted, !Task.isCancelled else { return }
                isLoading = false
                await realtimeManager.close()
            }
        }
    }

    func startGeneration(context: RealtimeContext) {
        guard let localMediaStream else {
            errorMessage = "本地媒体尚未准备好，请稍后重试。"
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
                isGenerationRequested = false
                remoteVideoTrack = nil
                isLoading = false
                await realtimeManager.disconnect()
            }
        }
    }

    func stopGeneration() {
        guard isGenerationRequested || remoteVideoTrack != nil else { return }

        isGenerationRequested = false
        remoteVideoTrack = nil
        isLoading = !isPreviewReady

        let previousTask = generationTask
        previousTask?.cancel()
        generationTask = Task { [weak self] in
            await previousTask?.value
            guard let self, !Task.isCancelled else { return }
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
                    isLoading = !isPreviewReady
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if !isGenerationRequested {
                    isLoading = !isPreviewReady
                }
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
        isPreviewReady = false
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
            await realtimeManager.setErrorListener(nil)
            await realtimeManager.setStateListener(nil)
            await realtimeManager.setCameraPreviewReadyListener(nil)
            await realtimeManager.close()
        }
    }

    private func renderRealtimeState(_ state: RealtimeState) {
        switch state.connectionState {
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
        case .idle, .disconnecting, .disconnected:
            if !isGenerationRequested {
                remoteVideoTrack = nil
                isLoading = !isPreviewReady
            }
        case .error:
            isGenerationRequested = false
            remoteVideoTrack = nil
            isLoading = !isPreviewReady
        }
    }

    private func handleRealtimeError(_ error: XmaxError) {
        guard error.code != .cancelled else { return }
        errorMessage = error.localizedDescription
    }
}
