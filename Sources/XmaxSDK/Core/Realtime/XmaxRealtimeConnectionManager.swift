import Foundation

typealias RealtimeConnectionValidity = @Sendable () -> Bool
typealias RealtimeConnectionHeartbeatFailureHandler = @Sendable (
    _ sessionID: String,
    _ error: XmaxError
) async -> Void

/// 协调服务端会话、RTC 房间、本地发布和远端媒体资源。
actor XmaxRealtimeConnectionManager {

    // 基础层组件
    private let rtcProvider: any RtcProviding

    // 服务层组件
    private let sessionService: any RealtimeSessionServicing

    // 业务层组件
    private let roomController: any RoomControlling
    private let remoteVideoController: any RemoteVideoControlling
    private let streamController: any StreamControlling

    // 连接资源
    private var activeRemoteTrack: RealtimeVideoTrack?
    private var activeSession: RealtimeSession?

    init(
        rtcProvider: any RtcProviding,
        sessionService: any RealtimeSessionServicing,
        roomController: any RoomControlling,
        remoteVideoController: any RemoteVideoControlling,
        streamController: any StreamControlling
    ) {
        self.rtcProvider = rtcProvider
        self.sessionService = sessionService
        self.roomController = roomController
        self.remoteVideoController = remoteVideoController
        self.streamController = streamController
    }

    var currentSessionID: String {
        activeSession?.id ?? ""
    }

    func updateRemoteVideoFormat(_ videoFormat: RealtimeVideoFormat) {
        activeRemoteTrack?.updateVideoFormat(videoFormat)
    }

    func connect(
        model: RealtimeModel,
        videoFormat: RealtimeVideoFormat,
        includeLocalAudio: Bool,
        isCurrent: @escaping RealtimeConnectionValidity,
        onHeartbeatFailure: @escaping RealtimeConnectionHeartbeatFailureHandler
    ) async throws -> RealtimeMediaStream {
        var session: RealtimeSession?
        var sessionActivated = false

        do {
            session = try await sessionService.createSession(model: model)
            try Self.ensureCurrent(isCurrent)
            guard let session,
                  let connection = session.connection else {
                throw XmaxError(
                    code: .sessionError,
                    message: "Session does not contain complete RTC join " +
                        "information"
                )
            }

            try await roomController.join(
                connection: connection,
                ensureActive: {
                    try Self.ensureCurrent(isCurrent)
                }
            )
            try Self.ensureCurrent(isCurrent)

            try streamController.configureRoom(
                roomID: connection.roomID,
                botName: connection.botName
            )
            try streamController.publishLocalStream(
                includeAudio: includeLocalAudio
            )
            try Self.ensureCurrent(isCurrent)

            sessionService.startHeartbeat(
                sessionID: session.id,
                onFailure: onHeartbeatFailure
            )
            let remoteTrack = RealtimeVideoTrack(
                id: connection.botName ?? "video-remote",
                videoFormat: videoFormat
            )
            await registerRemoteTrack(remoteTrack)

            activeSession = session
            activeRemoteTrack = remoteTrack
            sessionActivated = true
            try Self.ensureCurrent(isCurrent)

            return RealtimeMediaStream(
                id: StreamID.remote.rawValue,
                videoTrack: remoteTrack
            )
        } catch {
            if isCurrent() {
                await rollbackConnection()
            }

            if let session, !sessionActivated {
                await closeSessionAfterFailedConnection(session.id)
            }
            guard isCurrent() else {
                throw XmaxError(
                    code: .cancelled,
                    message: "Realtime connection was cancelled"
                )
            }
            throw XmaxError.from(error)
        }
    }

    @discardableResult
    func disconnect(fallbackSessionID: String? = nil) async -> String? {
        let session = activeSession
        let remoteTrack = activeRemoteTrack
        activeSession = nil
        activeRemoteTrack = nil

        sessionService.stopHeartbeat()
        await resetRemoteRendering(track: remoteTrack)
        await streamController.resetRoom()
        await roomController.leave()

        let sessionID = session?.id ?? fallbackSessionID
        if let sessionID {
            do {
                try await sessionService.closeSession(sessionID: sessionID)
            } catch {
                Self.logCleanupFailure(
                    operation: "关闭实时会话",
                    error: error
                )
            }
        }
        return sessionID
    }
}

private extension XmaxRealtimeConnectionManager {
    static func ensureCurrent(
        _ isCurrent: RealtimeConnectionValidity
    ) throws {
        guard isCurrent() else {
            throw XmaxError(
                code: .cancelled,
                message: "Realtime connection was cancelled"
            )
        }
    }

    @MainActor
    func registerRemoteTrack(_ track: RealtimeVideoTrack) {
        let remoteVideoController = remoteVideoController
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                libraryName: rtcProvider.renderLibraryName,
                attachHandler: { view, contentMode in
                    try remoteVideoController.attach(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: {
                    try remoteVideoController.detach()
                }
            )
        )
    }

    func rollbackConnection() async {
        let remoteTrack = activeRemoteTrack
        activeSession = nil
        activeRemoteTrack = nil

        sessionService.stopHeartbeat()
        await resetRemoteRendering(track: remoteTrack)
        await streamController.resetRoom()
        await roomController.leave()
    }

    @MainActor
    func resetRemoteRendering(track: RealtimeVideoTrack?) {
        if let track {
            VideoRenderRegistry.unregister(track)
        }
        do {
            try remoteVideoController.reset()
        } catch {
            Self.logCleanupFailure(
                operation: "重置远端视频渲染",
                error: error
            )
        }
    }

    func closeSessionAfterFailedConnection(_ sessionID: String) async {
        do {
            try await sessionService.closeSession(sessionID: sessionID)
        } catch {
            Self.logCleanupFailure(
                operation: "连接回滚关闭会话",
                error: error
            )
        }
    }

    nonisolated static func logCleanupFailure(
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
