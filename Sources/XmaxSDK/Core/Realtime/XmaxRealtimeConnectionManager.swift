//
//  XmaxRealtimeConnectionManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A closure that indicates whether a connection operation is still current.
///
/// - Returns: `true` if the operation belongs to the current connection lifecycle.
typealias RealtimeConnectionValidity = @Sendable () -> Bool

/// An asynchronous handler for a session heartbeat failure.
///
/// - Parameters:
///   - sessionID: The identifier of the session whose heartbeat failed.
///   - error: The error reported by the heartbeat request.
typealias RealtimeConnectionHeartbeatFailureHandler =
    @Sendable (
        _ sessionID: String,
        _ error: XmaxError
    ) async -> Void

/// Manages server sessions, RTC connections, and remote media resources.
actor XmaxRealtimeConnectionManager {

    /// The service that creates, maintains, and closes server sessions.
    private let sessionService: any RealtimeSessionServicing

    /// The media component that handles interactions from the remote video view.
    private let interactionController: any InteractionControlling

    /// The controller that manages remote video rendering.
    private let renderController: any RenderControlling

    /// The controller that manages RTC connections and local stream publishing.
    private let streamController: any StreamControlling

    /// The recorder for connection startup timings.
    private let timing: RealtimeTiming

    /// The remote video track for the current connection.
    private var activeRemoteTrack: RealtimeVideoTrack?

    /// The server session owned by this connection.
    private var activeSession: RealtimeSession?

    /// The most recently applied target dimensions for server output, in pixels.
    private(set) var currentTargetSize: CGSize?

    /// Creates a connection manager with the specified services and controllers.
    init(
        sessionService: any RealtimeSessionServicing,
        interactionController: any InteractionControlling,
        renderController: any RenderControlling,
        streamController: any StreamControlling,
        timing: RealtimeTiming = RealtimeTiming()
    ) {
        self.sessionService = sessionService
        self.interactionController = interactionController
        self.renderController = renderController
        self.streamController = streamController
        self.timing = timing
    }

    /// The active session identifier, or an empty string if no session is active.
    var currentSessionID: String {
        activeSession?.id ?? ""
    }

    /// The remote media stream for the active session.
    ///
    /// This value is `nil` until both the session and remote video track are available.
    var currentRemoteStream: RealtimeMediaStream? {
        guard activeSession != nil, let activeRemoteTrack else {
            return nil
        }
        return RealtimeMediaStream(
            id: StreamID.remote.rawValue,
            videoTrack: activeRemoteTrack
        )
    }

    /// Updates the remote track's format using the current target dimensions.
    ///
    /// - Parameter videoFormat: The resolved local media format. Its dimensions are replaced by the
    ///   target dimensions, if set.
    func updateRemoteVideoFormat(
        _ videoFormat: RealtimeVideoFormat
    ) async {
        guard let activeRemoteTrack else {
            return
        }
        let remoteFormat = remoteVideoFormat(for: videoFormat)
        activeRemoteTrack.updateVideoFormat(remoteFormat)
    }

    /// Updates target output dimensions and the remote track's format.
    ///
    /// - Parameters:
    ///   - size: The target dimensions of the server's output video, in pixels.
    ///   - videoFormat: The resolved local media format, whose frame rate and encoding options are
    ///     preserved.
    func updateTargetSize(
        _ size: CGSize,
        videoFormat: RealtimeVideoFormat
    ) async {
        guard activeSession != nil else {
            return
        }
        currentTargetSize = size
        await updateRemoteVideoFormat(videoFormat)
    }

    /// Establishes a realtime session and prepares its remote stream.
    ///
    /// The returned stream may not yet have a displayable frame.
    ///
    /// - Parameters:
    ///   - model: The generation model for this session.
    ///   - videoFormat: The resolved local media format used to initialize the interaction
    ///     coordinate space and remote track.
    ///   - targetSize: The server's target output dimensions, or `nil` to use the resolved media
    ///     dimensions.
    ///   - includeLocalAudio: Whether to publish local audio.
    ///   - isCurrent: A closure that indicates whether this connection operation is still current.
    ///   - onHeartbeatFailure: The handler for heartbeat errors from this session.
    ///
    /// - Returns: The remote media stream for the established connection.
    ///
    /// - Throws: An error if session creation, RTC connection, or local publishing fails, or if the
    ///   connection operation is cancelled.
    func connect(
        model: RealtimeModel,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        includeLocalAudio: Bool,
        isCurrent: @escaping RealtimeConnectionValidity,
        onHeartbeatFailure: @escaping RealtimeConnectionHeartbeatFailureHandler
    ) async throws -> RealtimeMediaStream {
        currentTargetSize = targetSize
        var session: RealtimeSession?
        var sessionActivated = false

        do {
            timing.beginSessionCreation()
            session = try await sessionService.createSession(model: model)
            timing.finishSessionCreation()
            try Self.ensureCurrent(isCurrent)
            guard let session,
                let connection = session.connection
            else {
                throw XmaxError(
                    code: .sessionError,
                    message: "Session does not contain complete RTC join " + "information"
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
                videoFormat: remoteVideoFormat(for: videoFormat)
            )
            await registerRemoteTrack(
                remoteTrack,
                resolvedMediaSize: videoFormat.size
            )

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

    /// Disconnects RTC, releases remote rendering resources, and closes the server session.
    ///
    /// - Returns: The identifier of the closed session, or `nil` if no session was active.
    ///
    /// - Throws: An error if the server session can't be closed.
    @discardableResult
    func disconnect() async throws -> String? {
        let session = activeSession
        let remoteTrack = activeRemoteTrack
        activeSession = nil
        activeRemoteTrack = nil
        currentTargetSize = nil

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

    /// Derives a remote video format by applying the current target dimensions.
    ///
    /// - Parameter mediaFormat: The resolved local media format.
    ///
    /// - Returns: A format with the target dimensions, or the original format if no target
    ///   dimensions are set.
    func remoteVideoFormat(
        for mediaFormat: RealtimeVideoFormat
    ) -> RealtimeVideoFormat {
        guard let currentTargetSize else {
            return mediaFormat
        }
        return mediaFormat.resized(
            width: Int(currentTargetSize.width),
            height: Int(currentTargetSize.height)
        )
    }

    /// Verifies that a connection operation still belongs to the current lifecycle.
    ///
    /// - Parameter isCurrent: The closure that checks the operation's validity.
    ///
    /// - Throws: A cancellation error if the operation is no longer current.
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

    /// Registers a remote track for rendering and forwards view interactions to the media layer.
    ///
    /// - Parameters:
    ///   - track: The remote video track to register.
    ///   - resolvedMediaSize: The resolved local media dimensions used to map interaction
    ///     coordinates.
    func registerRemoteTrack(
        _ track: RealtimeVideoTrack,
        resolvedMediaSize: CGSize
    ) async {
        let interactionController = interactionController
        await renderController.registerRemoteTrack(
            track,
            resolvedMediaSize: resolvedMediaSize,
            interactionListener: { frame in
                await interactionController.submitInteraction(frame)
            }
        )
    }

    /// Releases resources after a failed connection attempt.
    func rollbackConnection() async {
        let remoteTrack = activeRemoteTrack
        activeSession = nil
        activeRemoteTrack = nil
        currentTargetSize = nil

        sessionService.stopHeartbeat()
        await resetRemoteRendering(track: remoteTrack)
        await streamController.disconnect()
    }

    /// Releases remote rendering resources.
    ///
    /// - Parameter track: The remote track to reset, or `nil` to clear rendering state without a
    ///   bound track.
    func resetRemoteRendering(
        track: RealtimeVideoTrack?
    ) async {
        do {
            try await renderController.resetRemoteTrack(track)
        } catch {
            XmaxLogger.realtime.error(
                message: """
                    重置远端视频渲染失败 (Failed to Reset Remote Video Rendering)
                    └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                    """
            )
        }
    }

    /// Closes a session after connection setup fails.
    ///
    /// - Parameter sessionID: The identifier of the session to close.
    func closeSessionAfterFailedConnection(
        _ sessionID: String
    ) async {
        do {
            try await sessionService.closeSession(sessionID: sessionID)
        } catch {
            XmaxLogger.realtime.error(
                message: """
                    连接回滚关闭会话失败 (Failed to Close Session During Connection Rollback)
                    └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                    """
            )
        }
    }
}
