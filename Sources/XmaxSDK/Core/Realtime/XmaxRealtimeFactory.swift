//
//  XmaxRealtimeFactory.swift
//  XmaxSDK
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// The shared components used by the public facade and its lifecycle manager.
struct XmaxRealtimeComponents: Sendable {
    let renderController: any RenderControlling
    let streamController: any StreamControlling
    let mediaController: any MediaControlling
    let mediaService: any MediaServicing
    let connectionManager: XmaxRealtimeConnectionManager
    let generationManager: XmaxRealtimeGenerationManager
    let errorManager: XmaxRealtimeErrorManager
    let timingManager: XmaxRealtimeTimingManager
    let lifecycleManager: XmaxRealtimeLifecycleManager
}

/// Creates realtime components and wires their frame, failure, and cleanup callbacks.
enum XmaxRealtimeFactory {
    @MainActor
    static func make(
        options: RealtimeConfiguration,
        apiService: any ApiServicing
    ) -> XmaxRealtimeComponents {
        let errorManager = XmaxRealtimeErrorManager()
        let rtcManager = RtcManager()
        let mediaService = MediaService(model: options.model)
        let timingManager = XmaxRealtimeTimingManager()

        let renderController = RenderController(
            rtcManager: rtcManager,
            frameInterpolationEnabled: options.isFrameInterpolationEnabled,
            frameInterpolationSupportChecker: {
                mediaService.supportsFrameInterpolation(for: $0)
            },
            errorListener: {
                errorManager.forward(
                    $0,
                    target: .connection
                )
            }
        )

        let streamController = StreamController(
            rtcManager: rtcManager,
            timingManager: timingManager,
            errorListener: {
                errorManager.forward(
                    $0,
                    target: .connection
                )
            },
            remoteStreamListener: { stream in
                try renderController.setRemoteStream(stream)
            }
        )

        let mediaController = MediaController(
            rtcManager: rtcManager,
            mediaService: mediaService,
            videoFrameListener: { frame in
                try streamController.pushLocalVideoFrame(frame)
            },
            audioFrameListener: { frame in
                try streamController.pushLocalAudioFrame(frame)
            },
            errorListener: {
                errorManager.forward(
                    $0,
                    target: .all
                )
            },
            interactionListener: { taskID, points in
                try await streamController.sendTracks(
                    taskID: taskID,
                    points: points
                )
            }
        )

        let connectionManager = XmaxRealtimeConnectionManager(
            errorManager: errorManager,
            timingManager: timingManager,
            interactionController: mediaController,
            renderController: renderController,
            streamController: streamController,
            sessionService: RealtimeSessionService(apiService: apiService),
            mediaService: mediaService
        )

        let generationManager = XmaxRealtimeGenerationManager(
            interactionController: mediaController,
            streamController: streamController,
            renderController: renderController,
            timingManager: timingManager
        )
        return assemble(
            streamController: streamController,
            mediaController: mediaController,
            renderController: renderController,
            mediaService: mediaService,
            connectionManager: connectionManager,
            generationManager: generationManager,
            errorManager: errorManager,
            timingManager: timingManager
        )
    }

    /// Wires the same lifecycle behavior for production and injected test components.
    static func assemble(
        streamController: any StreamControlling,
        mediaController: any MediaControlling,
        renderController: any RenderControlling,
        mediaService: any MediaServicing,
        connectionManager: XmaxRealtimeConnectionManager,
        generationManager: XmaxRealtimeGenerationManager,
        errorManager: XmaxRealtimeErrorManager,
        timingManager: XmaxRealtimeTimingManager
    ) -> XmaxRealtimeComponents {
        let lifecycleManager = XmaxRealtimeLifecycleManager(
            errorManager: errorManager,
            cleanup: { scope, taskID in
                if scope == .all {
                    await mediaController.setLocalAudioPreviewMuted(true)
                }

                do {
                    try await mediaController.stopMicrophoneCapture()
                } catch {
                    XmaxLogger.realtime.error(
                        message: """
                            停止麦克风采集失败 (Failed to Stop Microphone Capture)
                            └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                            """
                    )
                }

                do {
                    try await generationManager.reset(taskID: taskID)
                } catch {
                    XmaxLogger.realtime.error(
                        message: """
                            停止实时生成失败 (Failed to Stop Realtime Generation)
                            └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                            """
                    )
                }

                let activeSessionID = await connectionManager.currentSessionID
                var sessionID = activeSessionID.isEmpty ? nil : activeSessionID
                do {
                    sessionID = try await connectionManager.disconnect() ?? sessionID
                } catch {
                    XmaxLogger.realtime.error(
                        message: """
                            断开实时连接失败 (Failed to Disconnect Realtime)
                            └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                            """
                    )
                }

                if scope == .all {
                    await mediaController.stopLocalStream()
                } else {
                    await mediaController.setLocalAudioPreviewMuted(false)
                    do {
                        try await mediaController.updateCameraOrientation()
                    } catch {
                        XmaxLogger.realtime.error(
                            message: """
                                更新摄像头方向失败 (Failed to Update Camera Orientation)
                                └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                                """
                        )
                    }
                }
                return XmaxRealtimeLifecycleManager.CleanupResult(
                    sessionID: sessionID,
                    hasLocalMedia: await mediaController.currentTrack != nil
                )
            }
        )
        errorManager.setFailureHandler { [weak lifecycleManager] error, target, isCurrent in
            await lifecycleManager?.terminate(
                with: error,
                target: target,
                isCurrent: isCurrent
            )
        }
        return XmaxRealtimeComponents(
            renderController: renderController,
            streamController: streamController,
            mediaController: mediaController,
            mediaService: mediaService,
            connectionManager: connectionManager,
            generationManager: generationManager,
            errorManager: errorManager,
            timingManager: timingManager,
            lifecycleManager: lifecycleManager
        )
    }
}
