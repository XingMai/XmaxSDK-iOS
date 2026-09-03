import CoreGraphics
import Foundation

/// 协调相机权限、RTC 内部采集和本地预览资源。
final class CameraController: @unchecked Sendable {

    // 轨道标识
    private static let localVideoTrackID = "video0"

    // 基础层组件
    private let rtcManager: any RtcManaging
    private let permissionManager: any PermissionManaging

    // 服务层组件
    private let mediaService: any MediaServicing

    // 事件监听
    private let errorListener: XmaxErrorListener

    // 并发控制
    private let stateLock = NSLock()

    // 本地资源
    private var activeTrack: RealtimeVideoTrack?

    @MainActor
    convenience init(
        rtcManager: any RtcManaging,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.init(
            rtcManager: rtcManager,
            permissionManager: PermissionManager(),
            mediaService: MediaService(),
            errorListener: errorListener
        )
    }

    init(
        rtcManager: any RtcManaging,
        permissionManager: any PermissionManaging,
        mediaService: any MediaServicing,
        errorListener: @escaping XmaxErrorListener = { _ in }
    ) {
        self.rtcManager = rtcManager
        self.permissionManager = permissionManager
        self.mediaService = mediaService
        self.errorListener = errorListener
    }

    /// 当前活动的本地相机视频轨道；尚未创建时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
    }

    /// 设置摄像头预览就绪监听器，传入空值时清除监听器。
    func setPreviewReadyListener(
        _ listener: RealtimeCameraPreviewReadyListener?
    ) {
        rtcManager.setCameraPreviewReadyListener(listener)
    }

    /// 创建并启动本地相机流。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local camera stream before " +
                    "creating another one"
            )
        }

        return try await createStream(
            videoFormat: videoFormat,
            position: position
        )
    }

    /// 停止相机采集并释放本地预览绑定。
    func stopLocalCameraStream() async {
        let track = stateLock.withLock { () -> RealtimeVideoTrack? in
            let track = activeTrack
            activeTrack = nil
            return track
        }

        if let track {
            await MainActor.run {
                VideoRenderRegistry.unregister(track)
                do {
                    try rtcManager.unbindLocalVideo()
                } catch {
                    Self.logCleanupFailure(
                        title: "解除 RTC 本地预览绑定失败 (Failed to Detach RTC Local Preview)",
                        error: error
                    )
                }
            }
        }

        do {
            try rtcManager.stopVideoCapture()
        } catch {
            Self.logCleanupFailure(
                title: "停止 RTC 相机采集失败 (Failed to Stop RTC Camera Capture)",
                error: error
            )
        }
    }

    /// 在前置和后置摄像头之间切换。
    func switchCamera() async throws -> RealtimeMediaStream {
        guard let track = currentTrack,
              track.videoFormat != nil,
              let position = track.position else {
            throw XmaxError(
                code: .rtcError,
                message: "Local camera preview is not started"
            )
        }

        let nextPosition: CameraPosition = position == .front ? .back : .front
        do {
            try rtcManager.switchCamera(to: nextPosition)
            track.updatePosition(nextPosition)
            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: track
            )
        } catch {
            throw XmaxError.from(error)
        }
    }
}

private extension CameraController {
    func createStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        let resolvedFormat = try resolveVideoFormat(videoFormat)
        let track = RealtimeVideoTrack(
            id: Self.localVideoTrackID,
            videoFormat: resolvedFormat,
            position: position
        )

        do {
            try await permissionManager.ensureCameraPermission()
            try rtcManager.switchCamera(to: position)
            try rtcManager.startVideoCapture(
                width: resolvedFormat.width,
                height: resolvedFormat.height,
                frameRate: resolvedFormat.fps
            )

            await MainActor.run {
                VideoRenderRegistry.register(
                    track,
                    binding: VideoRenderBinding(
                        libraryName: rtcManager.renderLibraryName,
                        attachHandler: { view, contentMode in
                            do {
                                try self.rtcManager.bindLocalVideo(
                                    to: view,
                                    contentMode: contentMode
                                )
                            } catch {
                                self.errorListener(XmaxError.from(error))
                                throw error
                            }
                        },
                        detachHandler: { _ in
                            try self.rtcManager.unbindLocalVideo()
                        }
                    )
                )
            }
            stateLock.withLock {
                activeTrack = track
            }

            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: track
            )
        } catch {
            await MainActor.run {
                VideoRenderRegistry.unregister(track)
            }
            do {
                try rtcManager.stopVideoCapture()
            } catch {
                Self.logCleanupFailure(
                    title: "回滚 RTC 相机采集失败 (Failed to Roll Back RTC Camera Capture)",
                    error: error
                )
            }
            throw XmaxError.from(error)
        }
    }

    func resolveVideoFormat(
        _ videoFormat: RealtimeVideoFormat
    ) throws -> RealtimeVideoFormat {
        try videoFormat.validate()
        let targetSize = try mediaService.resolveModelInputSize(
            CGSize(width: videoFormat.width, height: videoFormat.height)
        )
        let resolvedFormat = RealtimeVideoFormat(
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            fps: videoFormat.fps
        )
        try resolvedFormat.validate()
        return resolvedFormat
    }

    static func logCleanupFailure(
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
