//
//  InteractionController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An asynchronous handler for task identifiers and normalized media trajectories.
typealias InteractionListener =
    @Sendable (
        _ taskID: String,
        _ points: [RealtimePoint]
    ) async throws -> Void

/// Maps view touches to normalized media coordinates and sends trajectories.
actor InteractionController: InteractionControlling {

    /// The interaction coordinate configuration for a task.
    private struct ActiveInteraction {

        /// The generation task receiving interactions.
        let taskID: String

        /// The resolved media dimensions used for normalization.
        let resolvedMediaSize: CGSize
    }

    /// The asynchronous task and normalized coordinate handler.
    private let listener: InteractionListener

    /// Interaction delivery state.

    /// The active interaction configuration.
    private var activeInteraction: ActiveInteraction?

    /// The latest unsent trajectory.
    private var pendingPoints: [RealtimePoint]?

    /// The task serializing trajectory sends.
    private var drainTask: Task<Void, Never>?

    /// The revision rejecting stale trajectory tasks.
    private var drainGeneration = 0

    /// Creates a trajectory interaction controller.
    init(
        listener: @escaping InteractionListener = { _, _ in
        }
    ) {
        self.listener = listener
    }

    /// Cancels pending trajectory delivery.
    deinit {
        drainTask?.cancel()
    }

    /// Starts accepting interactions for a generation task.
    ///
    /// - Parameters:
    ///   - taskID: The generation task identifier.
    ///   - videoFormat: The resolved media format used as the fixed coordinate baseline.
    func startInteraction(
        taskID: String,
        videoFormat: RealtimeVideoFormat
    ) {
        cancelPendingFrames()
        activeInteraction = ActiveInteraction(
            taskID: taskID,
            resolvedMediaSize: videoFormat.size
        )
    }

    /// Stops accepting interactions and clears the task.
    func stopInteraction() {
        activeInteraction = nil
        cancelPendingFrames()
    }

    /// Submits a touch trajectory.
    ///
    /// - Parameter frame: The view trajectory and viewport dimensions.
    func submitInteraction(
        _ frame: InteractionFrame
    ) {
        guard let activeInteraction,
            !frame.points.isEmpty
        else {
            return
        }

        let points = frame.points.compactMap {
            InteractionCoordinateMapper.map(
                $0,
                viewportSize: frame.viewportSize,
                resolvedMediaSize: activeInteraction.resolvedMediaSize,
                contentMode: frame.contentMode
            )
        }
        guard !points.isEmpty else {
            return
        }

        pendingPoints = points
        guard drainTask == nil else {
            return
        }
        let generation = drainGeneration
        drainTask = Task { [weak self] in
            await self?.drainPendingFrames(generation: generation)
        }
    }
}

private extension InteractionController {

    /// Invalidates the send task and clears pending trajectories.
    func cancelPendingFrames() {
        drainGeneration += 1
        pendingPoints = nil
        drainTask?.cancel()
        drainTask = nil
    }

    /// Sends the latest trajectory while the send revision remains current.
    ///
    /// - Parameter generation: The send loop revision.
    func drainPendingFrames(
        generation: Int
    ) async {
        while !Task.isCancelled,
            generation == drainGeneration,
            let interaction = activeInteraction,
            let points = pendingPoints
        {
            pendingPoints = nil
            do {
                try await listener(
                    interaction.taskID,
                    points
                )
            } catch is CancellationError {
                break
            } catch {
                XmaxLogger.interaction.warn(
                    message: "发送交互轨迹失败，已丢弃当前采样帧 "
                        + "(Failed to Send Interaction Trajectory; Current Sample Dropped)\n"
                        + "└─ \(XmaxLogger.localized("原因：", "Reason: "))"
                        + (error as NSError).localizedDescription
                )
            }
        }
        guard generation == drainGeneration else {
            return
        }
        drainTask = nil

        if activeInteraction != nil, pendingPoints != nil {
            drainTask = Task { [weak self] in
                await self?.drainPendingFrames(generation: generation)
            }
        }
    }
}
