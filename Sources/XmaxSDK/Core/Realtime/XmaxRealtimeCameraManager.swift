import CoreGraphics
import Foundation

/// 协调相机权限、RTC 内部采集、编码和本地预览资源。
final class XmaxRealtimeCameraManager: @unchecked Sendable {

    // 轨道标识
    private static let localVideoTrackID = "video0"

    // 基础层组件
    private let rtcManager: any RtcManaging
    private let permissionManager: any PermissionManaging

    // 服务层组件
    private let mediaService: any MediaServicing

    // 业务层组件
    private let encodingController: any EncodingControlling

    // 并发控制
    private let stateLock = NSLock()

    // 本地资源
    private var activeTrack: RealtimeVideoTrack?

    @MainActor
    convenience init(rtcManager: any RtcManaging) {
        self.init(
            rtcManager: rtcManager,
            permissionManager: PermissionManager(),
            mediaService: MediaService(),
            encodingController: EncodingController(rtcManager: rtcManager)
        )
    }

    init(
        rtcManager: any RtcManaging,
        permissionManager: any PermissionManaging,
        mediaService: any MediaServicing,
        encodingController: any EncodingControlling
    ) {
        self.rtcManager = rtcManager
        self.permissionManager = permissionManager
        self.mediaService = mediaService
        self.encodingController = encodingController
    }

    /// 当前活动的本地相机视频轨道；尚未创建时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
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

    /// 保留本地视频轨道并重新启动指定摄像头的采集。
    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        guard let track = currentTrack else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Create a local camera stream before replacing it"
            )
        }

        do {
            let resolvedFormat = try resolveVideoFormat(videoFormat)
            try rtcManager.stopVideoCapture()
            try encodingController.configure(resolvedFormat)
            try rtcManager.switchCamera(to: position)
            try rtcManager.startVideoCapture(
                width: resolvedFormat.width,
                height: resolvedFormat.height,
                frameRate: resolvedFormat.fps
            )
            track.updateVideoFormat(resolvedFormat)
            track.updatePosition(position)
            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: track
            )
        } catch {
            throw XmaxError.from(error)
        }
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
                        operation: "解除 RTC 本地预览绑定",
                        error: error
                    )
                }
            }
        }

        do {
            try rtcManager.stopVideoCapture()
        } catch {
            Self.logCleanupFailure(
                operation: "停止 RTC 相机采集",
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

private extension XmaxRealtimeCameraManager {
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
            try encodingController.configure(resolvedFormat)
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
                            try self.rtcManager.bindLocalVideo(
                                to: view,
                                contentMode: contentMode
                            )
                        },
                        detachHandler: {
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
                    operation: "回滚 RTC 相机采集",
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
        operation: String,
        error: any Error
    ) {
        XmaxLogger.error(
            "\(operation)失败\n└─ 原因：" +
                (error as NSError).localizedDescription,
            category: "Realtime"
        )
    }
}
