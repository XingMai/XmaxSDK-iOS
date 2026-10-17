//
//  RtcPlatformStub.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

@testable import XmaxSDK

/// 不创建厂商引擎的 RTC 替身。
final class RtcPlatformStub: RtcPlatform, @unchecked Sendable {

    // 房间工厂
    private let makeRoom: @Sendable (String) throws -> any RtcRoom

    init(makeRoom: @escaping @Sendable (String) throws -> any RtcRoom = { _ in RtcRoomStub() }) {
        self.makeRoom = makeRoom
    }

    func configureVideoEncoding(_ configuration: VideoEncodingConfiguration) throws {}
    func useExternalVideoSource() throws {}
    func configureLocalVideoMirror(for position: CameraPosition) throws {}
    func startAudioCapture() throws {}
    func stopAudioCapture() throws {}
    func startExternalAudioSource() throws {}
    func stopExternalAudioSource() throws {}
    func pushExternalVideoFrame(_ frame: VideoFrame) throws {}
    func pushExternalAudioFrame(_ frame: AudioFrame) throws {}

    func createRoom(roomID: String) throws -> any RtcRoom {
        try makeRoom(roomID)
    }
}

final class RtcRoomStub: RtcRoom, @unchecked Sendable {

    // 可控操作
    private let onJoin: @Sendable () throws -> Void
    private let onFlush: @Sendable () async throws -> Void

    // 监听及调用记录
    private let lock = NSLock()
    private var listener: (@Sendable (RtcRoomEvent) -> Void)?
    private var lastListener: (@Sendable (RtcRoomEvent) -> Void)?
    private var frameListener: RtcRemoteVideoFrameListener?
    private var destructions = 0
    private var sentMessages: [String] = []
    private var videoPublications: [Bool] = []
    private var joinedConfigurations: [RoomJoinConfiguration] = []

    var destroyCount: Int { lock.withLock { destructions } }
    var messages: [String] { lock.withLock { sentMessages } }
    var publishedVideo: [Bool] { lock.withLock { videoPublications } }
    var configurations: [RoomJoinConfiguration] { lock.withLock { joinedConfigurations } }

    init(
        onJoin: @escaping @Sendable () throws -> Void = {},
        onFlush: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.onJoin = onJoin
        self.onFlush = onFlush
    }

    func setEventListener(_ listener: (@Sendable (RtcRoomEvent) -> Void)?) {
        lock.withLock {
            self.listener = listener
            if let listener { lastListener = listener }
        }
    }

    func join(configuration: RoomJoinConfiguration) throws {
        lock.withLock { joinedConfigurations.append(configuration) }
        try onJoin()
    }

    func destroy() {
        lock.withLock {
            destructions += 1
            listener = nil
        }
    }

    func emit(_ event: RtcRoomEvent, late: Bool = false) {
        let callback = lock.withLock { late ? lastListener : listener }
        callback?(event)
    }

    func publishLocalVideo(_ publish: Bool) throws {
        lock.withLock { videoPublications.append(publish) }
    }

    func publishLocalAudio(_ publish: Bool) throws {}
    func subscribeRemoteVideo(userID: String, subscribe: Bool) throws {}
    func subscribeRemoteAudio(userID: String, subscribe: Bool) throws {}
    func setRemoteAudioVolume(_ volume: Int, for userID: String) throws {}

    func setRemoteVideoFrameListener(_ listener: RtcRemoteVideoFrameListener?, for userID: String)
        throws
    {
        lock.withLock { frameListener = listener }
    }

    func emitFrame(_ frame: RealtimeVideoFrame) {
        let callback = lock.withLock { frameListener }
        callback?(frame)
    }

    @discardableResult
    func sendRoomMessage(_ message: String, reportFailure: Bool = true) throws -> Task<Void, any Error> {
        lock.withLock { sentMessages.append(message) }
        return Task {}
    }

    func awaitPendingMessages() async throws {
        try await onFlush()
    }
}
