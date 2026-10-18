//
//  XmaxRealtimeConnectionManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 判断当前连接操作是否仍有效。
///
/// - Returns: 连接操作有效时返回 `true`。
typealias RealtimeConnectionValidity = @Sendable () -> Bool

/// 接收指定会话的心跳失败通知。
///
/// - Parameters:
///   - sessionID: 心跳失败的会话标识。
///   - error: 会话心跳产生的错误。
typealias RealtimeConnectionHeartbeatFailureHandler = @Sendable (
    _ sessionID: String,
    _ error: XmaxError
) async -> Void

/// 协调服务端会话、RTC 房间、本地发布和远端媒体资源。
actor XmaxRealtimeConnectionManager {

    /// 服务层组件
    private let sessionService: any RealtimeSessionServicing

    /// 媒体层组件
    private let interactionController: any InteractionControlling

    /// 渲染层组件
    private let renderController: any RenderControlling

    /// 传输层组件
    private let streamController: any StreamControlling

    /// 耗时统计
    private let timing: RealtimeTiming

    /// 连接资源
    private var activeRemoteTrack: RealtimeVideoTrack?
    private var activeSession: RealtimeSession?
    private(set) var currentTargetSize: CGSize?

    /// 创建实时连接管理器。
    ///
    /// - Parameters:
    ///   - sessionService: 负责创建、保活和关闭服务端会话的服务。
    ///   - interactionController: 接收远端渲染视图交互的媒体组件。
    ///   - renderController: 管理远端轨道渲染的组件。
    ///   - streamController: 管理 RTC 连接与本地流发布的组件。
    ///   - timing: 记录连接启动阶段耗时的组件。
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

    /// 当前会话标识；没有活跃会话时为空字符串。
    var currentSessionID: String {
        activeSession?.id ?? ""
    }

    /// 当前连接的远端媒体流；会话或轨道尚未准备好时为 `nil`。
    var currentRemoteStream: RealtimeMediaStream? {
        guard activeSession != nil, let activeRemoteTrack else {
            return nil
        }
        return RealtimeMediaStream(
            id: StreamID.remote.rawValue,
            videoTrack: activeRemoteTrack
        )
    }

    /// 根据当前回传尺寸更新远端轨道与渲染规格。
    ///
    /// - Parameter videoFormat: 处理后的本地媒体规格；配置了回传尺寸时，以回传宽高更新轨道。
    func updateRemoteVideoFormat(
        _ videoFormat: RealtimeVideoFormat
    ) async {
        guard let activeRemoteTrack else { return }
        let remoteFormat = remoteVideoFormat(for: videoFormat)
        activeRemoteTrack.updateVideoFormat(remoteFormat)
    }

    /// 保存当前连接的回传尺寸，并同步更新远端渲染规格。
    ///
    /// - Parameters:
    ///   - size: 服务端回传视频的目标尺寸，单位为像素。
    ///   - videoFormat: 处理后的本地媒体规格，用于保留帧率等非尺寸配置。
    func updateTargetSize(
        _ size: CGSize,
        videoFormat: RealtimeVideoFormat
    ) async {
        guard activeSession != nil else { return }
        currentTargetSize = size
        await updateRemoteVideoFormat(videoFormat)
    }

    /// 创建服务端会话、连接 RTC 并发布本地流，返回已注册的远端媒体流。
    ///
    /// - Parameters:
    ///   - model: 本次会话使用的生成模型。
    ///   - videoFormat: 处理后的本地媒体规格，用于初始化交互坐标基准和远端轨道。
    ///   - targetSize: 回传视频尺寸；传入 `nil` 时使用处理后的媒体尺寸。
    ///   - includeLocalAudio: 是否发布本地音频。
    ///   - isCurrent: 判断连接操作是否仍有效的回调。
    ///   - onHeartbeatFailure: 接收当前会话心跳错误的回调。
    /// - Returns: 已注册渲染与交互能力的远端媒体流；画面是否可用由后续首帧确认决定。
    /// - Throws: 会话创建、RTC 连接或本地流发布失败，以及连接操作被取消时抛出错误。
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
                videoFormat: remoteVideoFormat(for: videoFormat)
            )
            await registerRemoteTrack(remoteTrack, resolvedMediaSize: videoFormat.size)

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

    /// 断开 RTC、释放远端渲染资源，并关闭服务端会话。
    ///
    /// - Returns: 已关闭的会话标识；没有活跃会话时返回 `nil`。
    /// - Throws: 服务端会话关闭失败时抛出错误。
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
    /// 将当前回传尺寸应用到本地媒体规格。
    ///
    /// - Parameter mediaFormat: 处理后的本地媒体规格。
    /// - Returns: 采用回传宽高的视频规格；未设置回传尺寸时返回原规格。
    func remoteVideoFormat(for mediaFormat: RealtimeVideoFormat) -> RealtimeVideoFormat {
        guard let currentTargetSize else { return mediaFormat }
        return mediaFormat.resized(
            width: Int(currentTargetSize.width),
            height: Int(currentTargetSize.height)
        )
    }

    /// 确认连接操作仍属于当前生命周期。
    ///
    /// - Parameter isCurrent: 返回连接操作有效性的回调。
    /// - Throws: 连接操作已失效时抛出取消错误。
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

    /// 注册远端轨道渲染，并将视图交互转交媒体交互组件。
    ///
    /// - Parameters:
    ///   - track: 需要注册的远端视频轨道。
    ///   - resolvedMediaSize: 处理后的本地媒体尺寸，用于轨迹交互映射。
    func registerRemoteTrack(_ track: RealtimeVideoTrack, resolvedMediaSize: CGSize) async {
        let interactionController = interactionController
        await renderController.registerRemoteTrack(
            track,
            resolvedMediaSize: resolvedMediaSize,
            interactionListener: { frame in
                await interactionController.submitInteraction(frame)
            }
        )
    }

    /// 清除本地连接状态，停止心跳并释放远端渲染与 RTC 资源。
    func rollbackConnection() async {
        let remoteTrack = activeRemoteTrack
        activeSession = nil
        activeRemoteTrack = nil
        currentTargetSize = nil

        sessionService.stopHeartbeat()
        await resetRemoteRendering(track: remoteTrack)
        await streamController.disconnect()
    }

    /// 释放远端轨道的渲染资源，失败时记录日志。
    ///
    /// - Parameter track: 需要重置的远端轨道；可传入 `nil` 清理未绑定轨道的渲染状态。
    func resetRemoteRendering(track: RealtimeVideoTrack?) async {
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

    /// 关闭连接未成功建立的服务端会话，失败时记录日志。
    ///
    /// - Parameter sessionID: 需要关闭的会话标识。
    func closeSessionAfterFailedConnection(_ sessionID: String) async {
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
