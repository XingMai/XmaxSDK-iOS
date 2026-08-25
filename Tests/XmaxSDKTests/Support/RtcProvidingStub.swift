import Foundation
import UIKit
@testable import XmaxSDK

enum RtcProvidingCall: Equatable {
    case initialize
    case destroy
    case configureVideoEncoding(VideoEncodingConfiguration)
    case startVideoCapture(width: Int, height: Int, frameRate: Int)
    case stopVideoCapture
    case switchCamera(CameraPosition)
    case bindLocalVideo(VideoContentMode)
    case unbindLocalVideo
}

final class RtcProvidingStub: RtcProviding, @unchecked Sendable {

    // 测试配置
    private let encodingError: (any Error)?
    private let initializationError: (any Error)?
    private let startVideoCaptureError: (any Error)?
    private let stopVideoCaptureError: (any Error)?
    private let switchCameraError: (any Error)?
    private let bindLocalVideoError: (any Error)?
    private let unbindLocalVideoError: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [RtcProvidingCall] = []

    init(
        initializationError: (any Error)? = nil,
        encodingError: (any Error)? = nil,
        startVideoCaptureError: (any Error)? = nil,
        stopVideoCaptureError: (any Error)? = nil,
        switchCameraError: (any Error)? = nil,
        bindLocalVideoError: (any Error)? = nil,
        unbindLocalVideoError: (any Error)? = nil
    ) {
        self.initializationError = initializationError
        self.encodingError = encodingError
        self.startVideoCaptureError = startVideoCaptureError
        self.stopVideoCaptureError = stopVideoCaptureError
        self.switchCameraError = switchCameraError
        self.bindLocalVideoError = bindLocalVideoError
        self.unbindLocalVideoError = unbindLocalVideoError
    }

    var calls: [RtcProvidingCall] {
        lock.withLock { storedCalls }
    }

    var encodingConfigurations: [VideoEncodingConfiguration] {
        calls.compactMap { call in
            guard case let .configureVideoEncoding(configuration) = call else {
                return nil
            }
            return configuration
        }
    }

    func initialize() async throws {
        try lock.withLock {
            storedCalls.append(.initialize)
            if let initializationError {
                throw initializationError
            }
        }
    }

    func destroy() async {
        lock.withLock {
            storedCalls.append(.destroy)
        }
    }

    func configureVideoEncoding(
        _ configuration: VideoEncodingConfiguration
    ) throws {
        try lock.withLock {
            storedCalls.append(.configureVideoEncoding(configuration))
            if let encodingError {
                throw encodingError
            }
        }
    }

    func startVideoCapture(
        width: Int,
        height: Int,
        frameRate: Int
    ) throws {
        try lock.withLock {
            storedCalls.append(.startVideoCapture(
                width: width,
                height: height,
                frameRate: frameRate
            ))
            if let startVideoCaptureError {
                throw startVideoCaptureError
            }
        }
    }

    func stopVideoCapture() throws {
        try lock.withLock {
            storedCalls.append(.stopVideoCapture)
            if let stopVideoCaptureError {
                throw stopVideoCaptureError
            }
        }
    }

    func switchCamera(to position: CameraPosition) throws {
        try lock.withLock {
            storedCalls.append(.switchCamera(position))
            if let switchCameraError {
                throw switchCameraError
            }
        }
    }

    func useExternalVideoSource() throws {}

    func startExternalAudioSource() throws {}

    func stopExternalAudioSource() throws {}

    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws {}

    func pushExternalVideoFrame(
        _ frame: any VideoFrame,
        seiData: Data?
    ) throws {}

    func pushExternalAudioFrame(_ frame: AudioFrame) throws {}

    func joinRoom(
        configuration: RoomJoinConfiguration
    ) async throws {}

    func leaveRoom() async {}

    func publishLocalVideo() throws {}

    func unpublishLocalVideo() throws {}

    func publishLocalAudio() throws {}

    func unpublishLocalAudio() throws {}

    func subscribeRemoteVideo(
        userID: String,
        subscribe: Bool
    ) throws {}

    @MainActor
    func bindLocalVideo(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        try lock.withLock {
            storedCalls.append(.bindLocalVideo(contentMode))
            if let bindLocalVideoError {
                throw bindLocalVideoError
            }
        }
    }

    @MainActor
    func unbindLocalVideo() throws {
        try lock.withLock {
            storedCalls.append(.unbindLocalVideo)
            if let unbindLocalVideoError {
                throw unbindLocalVideoError
            }
        }
    }

    @MainActor
    func bindRemoteVideo(
        _ stream: RemoteStream,
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {}

    @MainActor
    func unbindRemoteVideo(_ stream: RemoteStream) throws {}

    var renderLibraryName: String {
        "test"
    }

    func sendRoomMessage(_ message: String) throws {}

    func setEventListener(_ listener: (any RtcEventListener)?) {}

    func setQualityListener(_ listener: (any RtcQualityListener)?) {}
}
