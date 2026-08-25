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
    case useExternalVideoSource
    case startExternalAudioSource
    case stopExternalAudioSource
    case pushExternalVideoFrame(seiData: Data?)
    case pushExternalAudioFrame(AudioFrame)
    case publishLocalVideo
    case unpublishLocalVideo
    case publishLocalAudio
    case unpublishLocalAudio
    case subscribeRemoteVideo(userID: String, subscribe: Bool)
    case joinRoom(RoomJoinConfiguration)
    case leaveRoom
    case sendRoomMessage(String)
    case bindLocalVideo(VideoContentMode)
    case unbindLocalVideo
    case bindRemoteVideo(RemoteStream, VideoContentMode)
    case unbindRemoteVideo(RemoteStream)
}

final class RtcProvidingStub: RtcProviding, @unchecked Sendable {

    typealias JoinRoomHandler = @Sendable (
        RoomJoinConfiguration
    ) async throws -> Void
    typealias LeaveRoomHandler = @Sendable () async -> Void

    // 测试配置
    private let encodingError: (any Error)?
    private let initializationError: (any Error)?
    private let startVideoCaptureError: (any Error)?
    private let stopVideoCaptureError: (any Error)?
    private let switchCameraError: (any Error)?
    private let publishLocalVideoError: (any Error)?
    private let unpublishLocalVideoError: (any Error)?
    private let publishLocalAudioError: (any Error)?
    private let unpublishLocalAudioError: (any Error)?
    private let subscribeRemoteVideoError: (any Error)?
    private let joinRoomError: (any Error)?
    private let sendRoomMessageError: (any Error)?
    private let joinRoomHandler: JoinRoomHandler?
    private let leaveRoomHandler: LeaveRoomHandler?
    private let bindLocalVideoError: (any Error)?
    private let unbindLocalVideoError: (any Error)?
    private let bindRemoteVideoError: (any Error)?
    private let unbindRemoteVideoError: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [RtcProvidingCall] = []
    private weak var storedEventListener: (any RtcEventListener)?
    private weak var storedQualityListener: (any RtcQualityListener)?

    init(
        initializationError: (any Error)? = nil,
        encodingError: (any Error)? = nil,
        startVideoCaptureError: (any Error)? = nil,
        stopVideoCaptureError: (any Error)? = nil,
        switchCameraError: (any Error)? = nil,
        publishLocalVideoError: (any Error)? = nil,
        unpublishLocalVideoError: (any Error)? = nil,
        publishLocalAudioError: (any Error)? = nil,
        unpublishLocalAudioError: (any Error)? = nil,
        subscribeRemoteVideoError: (any Error)? = nil,
        joinRoomError: (any Error)? = nil,
        sendRoomMessageError: (any Error)? = nil,
        joinRoomHandler: JoinRoomHandler? = nil,
        leaveRoomHandler: LeaveRoomHandler? = nil,
        bindLocalVideoError: (any Error)? = nil,
        unbindLocalVideoError: (any Error)? = nil,
        bindRemoteVideoError: (any Error)? = nil,
        unbindRemoteVideoError: (any Error)? = nil
    ) {
        self.initializationError = initializationError
        self.encodingError = encodingError
        self.startVideoCaptureError = startVideoCaptureError
        self.stopVideoCaptureError = stopVideoCaptureError
        self.switchCameraError = switchCameraError
        self.publishLocalVideoError = publishLocalVideoError
        self.unpublishLocalVideoError = unpublishLocalVideoError
        self.publishLocalAudioError = publishLocalAudioError
        self.unpublishLocalAudioError = unpublishLocalAudioError
        self.subscribeRemoteVideoError = subscribeRemoteVideoError
        self.joinRoomError = joinRoomError
        self.sendRoomMessageError = sendRoomMessageError
        self.joinRoomHandler = joinRoomHandler
        self.leaveRoomHandler = leaveRoomHandler
        self.bindLocalVideoError = bindLocalVideoError
        self.unbindLocalVideoError = unbindLocalVideoError
        self.bindRemoteVideoError = bindRemoteVideoError
        self.unbindRemoteVideoError = unbindRemoteVideoError
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

    func useExternalVideoSource() throws {
        lock.withLock {
            storedCalls.append(.useExternalVideoSource)
        }
    }

    func startExternalAudioSource() throws {
        lock.withLock {
            storedCalls.append(.startExternalAudioSource)
        }
    }

    func stopExternalAudioSource() throws {
        lock.withLock {
            storedCalls.append(.stopExternalAudioSource)
        }
    }

    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws {}

    func pushExternalVideoFrame(
        _ frame: any VideoFrame,
        seiData: Data?
    ) throws {
        lock.withLock {
            storedCalls.append(.pushExternalVideoFrame(seiData: seiData))
        }
    }

    func pushExternalAudioFrame(_ frame: AudioFrame) throws {
        lock.withLock {
            storedCalls.append(.pushExternalAudioFrame(frame))
        }
    }

    func joinRoom(
        configuration: RoomJoinConfiguration
    ) async throws {
        try record(.joinRoom(configuration), error: joinRoomError)
        try await joinRoomHandler?(configuration)
    }

    func leaveRoom() async {
        lock.withLock {
            storedCalls.append(.leaveRoom)
        }
        await leaveRoomHandler?()
    }

    func publishLocalVideo() throws {
        try record(.publishLocalVideo, error: publishLocalVideoError)
    }

    func unpublishLocalVideo() throws {
        try record(.unpublishLocalVideo, error: unpublishLocalVideoError)
    }

    func publishLocalAudio() throws {
        try record(.publishLocalAudio, error: publishLocalAudioError)
    }

    func unpublishLocalAudio() throws {
        try record(.unpublishLocalAudio, error: unpublishLocalAudioError)
    }

    func subscribeRemoteVideo(
        userID: String,
        subscribe: Bool
    ) throws {
        try record(
            .subscribeRemoteVideo(userID: userID, subscribe: subscribe),
            error: subscribeRemoteVideoError
        )
    }

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
    ) throws {
        try lock.withLock {
            storedCalls.append(.bindRemoteVideo(stream, contentMode))
            if let bindRemoteVideoError {
                throw bindRemoteVideoError
            }
        }
    }

    @MainActor
    func unbindRemoteVideo(_ stream: RemoteStream) throws {
        try lock.withLock {
            storedCalls.append(.unbindRemoteVideo(stream))
            if let unbindRemoteVideoError {
                throw unbindRemoteVideoError
            }
        }
    }

    var renderLibraryName: String {
        "test"
    }

    func sendRoomMessage(_ message: String) throws {
        try record(
            .sendRoomMessage(message),
            error: sendRoomMessageError
        )
    }

    func setEventListener(_ listener: (any RtcEventListener)?) {
        lock.withLock {
            storedEventListener = listener
        }
    }

    func setQualityListener(_ listener: (any RtcQualityListener)?) {
        lock.withLock {
            storedQualityListener = listener
        }
    }
}

extension RtcProvidingStub {
    @MainActor
    func emitRemoteVideoPublished(
        userID: String,
        published: Bool
    ) {
        let listener = lock.withLock { storedEventListener }
        listener?.onRemoteVideoPublished(
            userID: userID,
            published: published
        )
    }

    @MainActor
    func emitNetworkQuality(
        uplink: RtcQualityLevel,
        downlink: RtcQualityLevel
    ) {
        let listener = lock.withLock { storedQualityListener }
        listener?.onNetworkQuality(
            uplink: uplink,
            downlink: downlink
        )
    }

    @MainActor
    func emitPerformanceAlarm(
        limited: Bool,
        suggestedWidth: Int,
        suggestedHeight: Int,
        suggestedFrameRate: Int
    ) {
        let listener = lock.withLock { storedQualityListener }
        listener?.onPerformanceAlarm(
            limited: limited,
            suggestedWidth: suggestedWidth,
            suggestedHeight: suggestedHeight,
            suggestedFrameRate: suggestedFrameRate
        )
    }

    @MainActor
    func emitSeiMessage(
        stream: RemoteStream,
        message: String
    ) {
        let listener = lock.withLock { storedEventListener }
        listener?.onSeiMessageReceived(
            stream: stream,
            message: message
        )
    }
}

private extension RtcProvidingStub {
    func record(
        _ call: RtcProvidingCall,
        error: (any Error)?
    ) throws {
        try lock.withLock {
            storedCalls.append(call)
            if let error {
                throw error
            }
        }
    }
}
