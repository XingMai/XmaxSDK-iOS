import Foundation

typealias RealtimeConnectionValidity = @Sendable () -> Bool
typealias RealtimeConnectionHeartbeatFailureHandler = @Sendable (
    _ sessionID: String,
    _ error: XmaxError
) async -> Void

/// 协调服务端会话、RTC 房间、本地发布和远端媒体资源。
actor XmaxRealtimeConnectionManager {

    // 服务层组件
    private let sessionService: any RealtimeSessionServicing

    // 媒体层组件
    private let interactionController: any InteractionControlling

    // 渲染层组件
    private let renderController: any RenderControlling

    // 传输层组件
    private let streamController: any StreamControlling

    // 连接资源
    private var activeRemoteTrack: RealtimeVideoTrack?
    private var activeSession: RealtimeSession?

    init(
        sessionService: any RealtimeSessionServicing,
        interactionController: any InteractionControlling,
        renderController: any RenderControlling,
        streamController: any StreamControlling
    ) {
        self.sessionService = sessionService
        self.interactionController = interactionController
        self.renderController = renderController
        self.streamController = streamController
    }

    var currentSessionID: String {
        activeSession?.id ?? ""
    }

    var currentRemoteStream: RealtimeMediaStream? {
        guard activeSession != nil, let activeRemoteTrack else {
            return nil
        }
        return RealtimeMediaStream(
            id: StreamID.remote.rawValue,
            videoTrack: activeRemoteTrack
        )
    }

    func updateRemoteVideoFormat(
        _ videoFormat: RealtimeVideoFormat
    ) async {
        guard let activeRemoteTrack else { return }
        activeRemoteTrack.updateVideoFormat(videoFormat)
        await renderController.updateRemoteVideoFormat(
            videoFormat,
            for: activeRemoteTrack
        )
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

            try await streamController.connect(
                connection: connection,
                includeLocalAudio: includeLocalAudio,
                ensureActive: {
                    try Self.ensureCurrent(isCurrent)
                }
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
    func disconnect() async throws -> String? {
        let session = activeSession
        let remoteTrack = activeRemoteTrack
        activeSession = nil
        activeRemoteTrack = nil

        sessionService.stopHeartbeat()
        await resetRemoteRendering(track: remoteTrack)
        await streamController.disconnect()

        let sessionID = session?.id
        if let sessionID {
            try await sessionService.closeSession(sessionID: sessionID)
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

    func registerRemoteTrack(_ track: RealtimeVideoTrack) async {
        let interactionController = interactionController
        await renderController.registerRemoteTrack(
            track,
            interactionListener: { frame in
                await interactionController.submitInteraction(frame)
            }
        )
    }

    func rollbackConnection() async {
        let remoteTrack = activeRemoteTrack
        activeSession = nil
        activeRemoteTrack = nil

        sessionService.stopHeartbeat()
        await resetRemoteRendering(track: remoteTrack)
        await streamController.disconnect()
    }

    func resetRemoteRendering(track: RealtimeVideoTrack?) async {
        await renderController.resetRemoteTrack(track)
    }

    func closeSessionAfterFailedConnection(_ sessionID: String) async {
        do {
            try await sessionService.closeSession(sessionID: sessionID)
        } catch {
            Self.logCleanupFailure(
                title: "连接回滚关闭会话失败 (Failed to Close Session During Connection Rollback)",
                error: error
            )
        }
    }

    nonisolated static func logCleanupFailure(
        title: String,
        error: any Error
    ) {
        XmaxLogger.error(
            "\(title)\n└─ 原因：" +
                (error as NSError).localizedDescription,
            category: "Realtime"
        )
    }
}
