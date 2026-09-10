import CoreGraphics
import Foundation

/// 协调系统摄像头采集、外部视频上传和 SDK 本地预览。
final class CameraController: @unchecked Sendable {

    // 轨道标识
    private static let localVideoTrackID = "video0"

    // 基础层组件
    private let rtcManager: any RtcManaging
    private let permissionManager: any PermissionManaging
    private let captureManager: any CameraCaptureManaging

    // 服务层组件
    private let mediaService: any MediaServicing

    // 事件监听
    private let videoFrameListener: MediaVideoFrameListener
    private let errorListener: XmaxErrorListener
    private var previewReadyListener: RealtimeCameraPreviewReadyListener?

    // 并发控制
    private let stateLock = NSLock()

    // 本地资源
    private var activeTrack: RealtimeVideoTrack?
    private var preview: Preview?

    // 预览状态
    private var hasCapturedFrame = false
    private var isPreviewAttached = false
    private var hasReportedPreviewReady = false

    // 麦克风配置与采集状态
    private var storedUseMicrophone = false
    private var isMicrophoneCapturing = false

    @MainActor
    convenience init(
        rtcManager: any RtcManaging,
        mediaService: any MediaServicing = MediaService(),
        videoFrameListener: @escaping MediaVideoFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.init(
            rtcManager: rtcManager,
            permissionManager: PermissionManager(),
            mediaService: mediaService,
            captureManager: CameraCaptureManager(),
            videoFrameListener: videoFrameListener,
            errorListener: errorListener
        )
    }

    init(
        rtcManager: any RtcManaging,
        permissionManager: any PermissionManaging,
        mediaService: any MediaServicing,
        captureManager: any CameraCaptureManaging,
        videoFrameListener: @escaping MediaVideoFrameListener = { _ in },
        errorListener: @escaping XmaxErrorListener = { _ in }
    ) {
        self.rtcManager = rtcManager
        self.permissionManager = permissionManager
        self.mediaService = mediaService
        self.captureManager = captureManager
        self.videoFrameListener = videoFrameListener
        self.errorListener = errorListener
    }

    /// 当前活动的本地相机视频轨道；尚未创建时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
    }

    /// 当前相机流是否配置为使用麦克风。
    var useMicrophone: Bool {
        stateLock.withLock { activeTrack != nil && storedUseMicrophone }
    }

    /// 设置摄像头预览就绪监听器，传入空值时清除监听器。
    func setPreviewReadyListener(_ listener: RealtimeCameraPreviewReadyListener?) {
        let track = stateLock.withLock {
            previewReadyListener = listener
            return activeTrack
        }
        if let track { notifyPreviewReady(for: track) }
    }

    /// 创建并启动本地相机流。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition,
        useMicrophone: Bool = false
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local camera stream before creating another one"
            )
        }
        let resolvedFormat = try resolveVideoFormat(videoFormat)
        let track = RealtimeVideoTrack(
            id: Self.localVideoTrackID,
            videoFormat: resolvedFormat,
            position: position
        )
        do {
            try await permissionManager.ensureCameraPermission()
            if useMicrophone {
                try await permissionManager.ensureMicrophonePermission()
            }
            try Task.checkCancellation()
            try rtcManager.useExternalVideoSource()
            try rtcManager.configureLocalVideoMirror(for: position)
            let preview = await makePreview(for: track, position: position)
            stateLock.withLock {
                activeTrack = track
                self.preview = preview
                storedUseMicrophone = useMicrophone
                hasCapturedFrame = false
                isPreviewAttached = false
                hasReportedPreviewReady = false
            }
            try await captureManager.start(
                videoFormat: VideoFormat(
                    width: resolvedFormat.width,
                    height: resolvedFormat.height,
                    pixelFormat: .nv12
                ),
                frameRate: resolvedFormat.fps,
                position: position,
                frameListener: { [weak self] frame in
                    try self?.handleFrame(frame, track: track, preview: preview)
                },
                errorListener: { [weak self] error in
                    guard let self, currentTrack === track else { return }
                    errorListener(error)
                }
            )
            try Task.checkCancellation()
            return RealtimeMediaStream(id: StreamID.local.rawValue, videoTrack: track)
        } catch {
            await stopLocalCameraStream()
            throw XmaxError.from(error)
        }
    }

    /// 在实时连接开始时启动麦克风，不开启本地回放。
    func startMicrophoneCapture() throws {
        try stateLock.withLock {
            guard activeTrack != nil, storedUseMicrophone, !isMicrophoneCapturing else { return }
            // 启动失败时也保留待停止状态，由连接清理回收可能已启动的设备。
            isMicrophoneCapturing = true
            try rtcManager.startAudioCapture()
        }
    }

    /// 停止麦克风采集，保留下一次连接所需的配置。
    func stopMicrophoneCapture() throws {
        try stateLock.withLock {
            guard isMicrophoneCapturing else { return }
            try rtcManager.stopAudioCapture()
            isMicrophoneCapturing = false
        }
    }

    /// 停止相机采集并释放本地预览绑定。
    func stopLocalCameraStream() async {
        do {
            try stopMicrophoneCapture()
        } catch {
            Self.logCleanupFailure(title: "停止麦克风采集失败 (Failed to Stop Microphone Capture)", error: error)
        }
        let resources = stateLock.withLock {
            let resources = (activeTrack, preview)
            activeTrack = nil
            preview = nil
            storedUseMicrophone = false
            isMicrophoneCapturing = false
            hasCapturedFrame = false
            isPreviewAttached = false
            hasReportedPreviewReady = false
            return resources
        }
        await captureManager.stop()
        resources.1?.dispatcher.reset()
        await MainActor.run {
            if let track = resources.0 { VideoRenderRegistry.unregister(track) }
            resources.1?.presenter.clear()
        }
    }

    /// 在前置和后置摄像头之间切换。
    func switchCamera() async throws -> RealtimeMediaStream {
        guard let track = currentTrack, let position = track.position else {
            throw XmaxError(code: .rtcError, message: "Local camera preview is not started")
        }
        let nextPosition: CameraPosition = position == .front ? .back : .front
        try await captureManager.switchCamera(to: nextPosition)
        do {
            try rtcManager.configureLocalVideoMirror(for: nextPosition)
        } catch {
            try? await captureManager.switchCamera(to: position)
            try? rtcManager.configureLocalVideoMirror(for: position)
            throw error
        }
        track.updatePosition(nextPosition)
        let preview = stateLock.withLock { self.preview }
        await preview?.presenter.setMirrored(nextPosition == .front)
        return RealtimeMediaStream(id: StreamID.local.rawValue, videoTrack: track)
    }
}

private extension CameraController {
    struct Preview: Sendable {
        let presenter: DecodedVideoPreviewPresenter
        let dispatcher: DecodedVideoPreviewDispatcher
    }

    @MainActor
    func makePreview(for track: RealtimeVideoTrack, position: CameraPosition) -> Preview {
        let presenter = DecodedVideoPreviewPresenter()
        presenter.setMirrored(position == .front)
        let preview = Preview(
            presenter: presenter,
            dispatcher: DecodedVideoPreviewDispatcher(presenter: presenter)
        )
        VideoRenderRegistry.register(track, binding: VideoRenderBinding(
            attachHandler: { [weak self] view, contentMode in
                guard let videoView = view as? XmaxVideoView else {
                    throw XmaxError(code: .invalidConfiguration, message: "Camera tracks require an XmaxVideoView")
                }
                presenter.attach(to: videoView, contentMode: contentMode)
                self?.stateLock.withLock { self?.isPreviewAttached = true }
                self?.notifyPreviewReady(for: track)
            },
            detachHandler: { [weak self] view in
                if let videoView = view as? XmaxVideoView { presenter.detach(from: videoView) }
                self?.stateLock.withLock { self?.isPreviewAttached = false }
            }
        ))
        return preview
    }

    func handleFrame(_ frame: VideoFrame, track: RealtimeVideoTrack, preview: Preview) throws {
        let accepted = try stateLock.withLock {
            guard activeTrack === track else { return false }
            preview.dispatcher.enqueue(frame)
            hasCapturedFrame = true
            try videoFrameListener(frame)
            return true
        }
        if accepted { notifyPreviewReady(for: track) }
    }

    func notifyPreviewReady(for track: RealtimeVideoTrack) {
        let shouldNotify = stateLock.withLock {
            activeTrack === track && hasCapturedFrame && isPreviewAttached &&
                !hasReportedPreviewReady && previewReadyListener != nil
        }
        guard shouldNotify else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let listener = stateLock.withLock { () -> RealtimeCameraPreviewReadyListener? in
                guard activeTrack === track, hasCapturedFrame, isPreviewAttached,
                      !hasReportedPreviewReady, let previewReadyListener else { return nil }
                hasReportedPreviewReady = true
                return previewReadyListener
            }
            listener?()
        }
    }

    func resolveVideoFormat(_ videoFormat: RealtimeVideoFormat) throws -> RealtimeVideoFormat {
        try videoFormat.validate()
        let targetSize = try mediaService.resolveModelInputSize(
            CGSize(width: videoFormat.width, height: videoFormat.height)
        )
        let resolvedFormat = videoFormat.resized(width: Int(targetSize.width), height: Int(targetSize.height))
        try resolvedFormat.validate()
        return resolvedFormat
    }

    static func logCleanupFailure(title: String, error: any Error) {
        XmaxLogger.error(
            category: "Realtime",
            message: "\(title)\n└─ 原因：" + (error as NSError).localizedDescription
        )
    }
}
