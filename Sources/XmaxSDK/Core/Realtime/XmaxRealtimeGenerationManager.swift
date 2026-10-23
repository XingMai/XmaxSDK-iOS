//
//  XmaxRealtimeGenerationManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A closure that verifies whether a generation operation is still current.
///
/// - Throws: An error if the operation is no longer current or has been cancelled.
typealias RealtimeGenerationValidity = @Sendable () throws -> Void

/// Coordinates generation signaling, remote stream confirmation, condition updates, and
/// interactions.
actor XmaxRealtimeGenerationManager {

    /// Generation dependencies.

    /// The controller that manages trajectory interactions during generation.
    private let interactionController: any InteractionControlling

    /// The controller that publishes local media and sends generation signaling.
    private let streamController: any StreamControlling

    /// The closure that generates identifiers for new tasks.
    private let taskIDGenerator: @Sendable () -> String

    /// Cached generation conditions.

    /// The prompt and reference image from the most recent successful request.
    private var currentContext: RealtimeContext?

    /// The face restoration setting from the most recent successful request.
    private var currentFaceRestoration = false

    /// The face restoration setting to reuse when restarting generation.
    var cachedFaceRestoration: Bool {
        currentFaceRestoration
    }

    /// Creates a manager for generation requests and interactions.
    init(
        interactionController: any InteractionControlling,
        streamController: any StreamControlling,
        taskIDGenerator: @escaping @Sendable () -> String =
            XmaxRealtimeGenerationManager.createTaskID
    ) {
        self.interactionController = interactionController
        self.streamController = streamController
        self.taskIDGenerator = taskIDGenerator
    }

    /// Verifies that the request supplies a context or can reuse a cached context.
    ///
    /// - Parameter context: The requested context, or `nil` to use the cached context.
    ///
    /// - Throws: An error if neither a supplied nor a cached context is available.
    func validateContext(
        _ context: RealtimeContext?
    ) throws {
        guard context != nil || currentContext != nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "A realtime context is required for the first generation"
            )
        }
    }

    /// Starts generation and waits for remote stream confirmation.
    ///
    /// - Parameters:
    ///   - videoFormat: The resolved local media format used for interaction coordinates.
    ///   - targetSize: The returned video dimensions, or `nil` to use the server default.
    ///   - context: The requested context, or `nil` to reuse the most recent successful context.
    ///   - faceRestoration: Whether to restore the original face.
    ///   - generationVideoFormat: The server generation format, or `nil` to use the local media
    ///     format.
    ///   - paddingContain: Whether to preserve the entire input within the generation canvas.
    ///   - ensureCurrent: A closure that verifies the operation is still current.
    ///
    /// - Returns: The task identifier whose remote stream has been confirmed.
    ///
    /// - Throws: An error if the context is missing, signaling or stream confirmation fails, or the
    ///   operation is invalidated.
    func start(
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        context: RealtimeContext?,
        faceRestoration: Bool = false,
        generationVideoFormat: RealtimeVideoFormat? = nil,
        paddingContain: Bool = false,
        ensureCurrent: @escaping RealtimeGenerationValidity
    ) async throws -> String {
        guard let resolvedContext = context ?? currentContext else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "A realtime context is required for the first generation"
            )
        }

        let taskID = taskIDGenerator()
        let confirmation = try await streamController.beginGeneration(
            taskID: taskID,
            videoFormat: generationVideoFormat ?? videoFormat,
            targetSize: targetSize,
            context: resolvedContext,
            faceRestoration: faceRestoration,
            paddingContain: paddingContain
        )
        do {
            try await withTaskCancellationHandler {
                try await confirmation.value
            } onCancel: {
                confirmation.cancel()
            }
            try ensureCurrent()

            await interactionController.startInteraction(
                taskID: taskID,
                videoFormat: videoFormat
            )
            try ensureCurrent()
            currentContext = resolvedContext
            currentFaceRestoration = faceRestoration
            return taskID
        } catch {
            try? await stop(taskID: taskID)
            throw XmaxError.from(error)
        }
    }

    /// Updates generation conditions and interactions without waiting for a new stream
    /// confirmation.
    ///
    /// - Parameters:
    ///   - taskID: The identifier of the generation task to update.
    ///   - videoFormat: The resolved local media format used for interaction coordinates.
    ///   - targetSize: The returned video dimensions, or `nil` to omit this setting.
    ///   - context: The requested context, or `nil` to reuse the most recent successful context.
    ///   - faceRestoration: Whether to restore the original face.
    ///   - generationVideoFormat: The server generation format, or `nil` to use the local media
    ///     format.
    ///   - paddingContain: Whether to preserve the entire input within the generation canvas.
    ///   - ensureCurrent: A closure that verifies the operation is still current.
    ///
    /// - Throws: An error if the context is missing, the update fails, or the operation is
    ///   invalidated.
    func update(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        context: RealtimeContext?,
        faceRestoration: Bool = false,
        generationVideoFormat: RealtimeVideoFormat? = nil,
        paddingContain: Bool = false,
        ensureCurrent: RealtimeGenerationValidity = {
        }
    ) async throws {
        guard let resolvedContext = context ?? currentContext else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "A realtime context is required for the first generation"
            )
        }

        try await streamController.updateGeneration(
            taskID: taskID,
            videoFormat: generationVideoFormat ?? videoFormat,
            targetSize: targetSize,
            context: resolvedContext,
            faceRestoration: faceRestoration,
            paddingContain: paddingContain
        )
        try ensureCurrent()
        await interactionController.startInteraction(
            taskID: taskID,
            videoFormat: videoFormat
        )
        try ensureCurrent()
        currentContext = resolvedContext
        currentFaceRestoration = faceRestoration
    }

    /// Stops interactions and sends a stop-generation signal.
    ///
    /// - Parameter taskID: The identifier of the generation task to stop.
    ///
    /// - Throws: An error if the stop-generation signal cannot be sent.
    func stop(
        taskID: String
    ) async throws {
        await interactionController.stopInteraction()
        try await streamController.stopGeneration(taskID: taskID)
    }

    /// Stops generation and clears cached conditions.
    ///
    /// - Parameter taskID: The task identifier, or an empty string if no task is specified.
    ///
    /// - Throws: An error if the stop-generation signal cannot be sent.
    func reset(
        taskID: String = ""
    ) async throws {
        currentContext = nil
        currentFaceRestoration = false
        try await stop(taskID: taskID)
    }

    /// Creates a random task identifier with an iOS platform marker.
    ///
    /// - Returns: An identifier in the form `task-<22 URL-safe characters>?os=ios`.
    nonisolated static func createTaskID() -> String {
        var uuid = UUID().uuid
        let data = withUnsafeBytes(of: &uuid) {
            Data($0)
        }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(
                of: "+",
                with: "-"
            )
            .replacingOccurrences(
                of: "/",
                with: "_"
            )
            .replacingOccurrences(
                of: "=",
                with: ""
            )
        return "task-\(encoded)?os=ios"
    }
}
