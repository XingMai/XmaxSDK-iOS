//
//  RealtimeState.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A realtime connection lifecycle state.
public enum RealtimeConnectionState: String, CaseIterable, Sendable {

    /// No local media stream is available.
    case idle = "Idle"

    /// Local media is preparing. Camera input also waits for a valid frame and attached preview.
    case preparing = "Preparing"

    /// Local media is ready for preview, connection, and generation.
    case ready = "Ready"

    /// A session is being created and its local stream connected and published.
    case connecting = "Connecting"

    /// The realtime connection is open without an active generation task.
    case connected = "Connected"

    /// The realtime connection is generating.
    case generating = "Generating"

    /// Generation, room, and session resources are being released.
    case disconnecting = "Disconnecting"

}

/// The reason for entering a realtime state.
public enum RealtimeReason: Equatable, Sendable {

    /// An explicit stop or normal resource release.
    case normal

    /// An orientation change requiring generation reconfiguration.
    case orientationChanged

    /// An operation or runtime failure ended the current lifecycle.
    case failure(XmaxError)
}

/// A snapshot of realtime lifecycle state.
public struct RealtimeState: Equatable, Sendable {

    /// The current connection state.
    public let connectionState: RealtimeConnectionState

    /// The current or most recent session identifier.
    public let sessionID: String?

    /// The generation task identifier.
    public let taskID: String?

    /// The reason for this state, cleared when a new operation begins.
    public let reason: RealtimeReason?

    /// Creates a realtime state snapshot.
    public init(
        connectionState: RealtimeConnectionState,
        sessionID: String? = nil,
        taskID: String? = nil,
        reason: RealtimeReason? = nil
    ) {
        self.connectionState = connectionState
        self.sessionID = sessionID
        self.taskID = taskID
        self.reason = reason
    }
}

/// A realtime state listener.
public typealias RealtimeStateListener =
    @MainActor @Sendable (
        RealtimeState
    ) -> Void
