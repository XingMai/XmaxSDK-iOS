//
//  XmaxRealtimeGenerationManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 确认当前生成操作仍有效。
///
/// - Throws: 操作已失效或被取消时抛出错误。
typealias RealtimeGenerationValidity = @Sendable () throws -> Void

/// 协调生成信令、远端结果确认、条件更新和轨迹交互。
actor XmaxRealtimeGenerationManager {

    // 业务层组件
    private let interactionController: any InteractionControlling
    private let streamController: any StreamControlling


    // 生成配置
    private let taskIDGenerator: @Sendable () -> String


    // 生成资源
    private var currentContext: RealtimeContext?
    private var currentFaceRestoration = false

    /// 自动重启生成时复用上次成功请求的人脸还原设置。
    var cachedFaceRestoration: Bool { currentFaceRestoration }

    /// 创建实时生成管理器。
    ///
    /// - Parameters:
    ///   - interactionController: 管理生成期间轨迹交互的组件。
    ///   - streamController: 发送生成信令并确认远端结果的组件。
    ///   - taskIDGenerator: 生成新任务标识的回调。
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

    /// 确认首次生成具有可用上下文，后续请求允许复用已缓存的上下文。
    ///
    /// - Parameter context: 本次生成上下文；传入 `nil` 时检查已有上下文。
    /// - Throws: 本次未提供上下文且没有可复用上下文时抛出错误。
    func validateContext(_ context: RealtimeContext?) throws {
        guard context != nil || currentContext != nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "A realtime context is required for the first generation"
            )
        }
    }

    /// 发送生成请求并等待结果流确认，成功后启用交互并缓存生成条件。
    ///
    /// - Parameters:
    ///   - videoFormat: 本地媒体规格，用于配置交互坐标。
    ///   - targetSize: 回传视频尺寸；传入 `nil` 时使用服务端默认回传尺寸。
    ///   - context: 本次生成上下文；传入 `nil` 时复用上次成功请求的上下文。
    ///   - faceRestoration: 是否启用人脸还原。
    ///   - generationVideoFormat: 服务端生成规格；传入 `nil` 时使用本地媒体规格。
    ///   - paddingContain: 是否使用保留完整内容的填充方式，并以显示尺寸计算交互坐标。
    ///   - ensureCurrent: 确认本次操作仍有效的回调。
    /// - Returns: 完成结果流确认的生成任务标识。
    /// - Throws: 上下文缺失、信令发送或结果流确认失败，以及操作失效时抛出错误。
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
                videoFormat: videoFormat,
                useDisplayedSize: paddingContain
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

    /// 更新当前任务的生成条件与交互配置，不等待新的结果流确认。
    ///
    /// - Parameters:
    ///   - taskID: 需要更新的生成任务标识。
    ///   - videoFormat: 本地媒体规格，用于配置交互坐标。
    ///   - targetSize: 回传视频尺寸；传入 `nil` 时不附加回传尺寸。
    ///   - context: 本次生成上下文；传入 `nil` 时复用上次成功请求的上下文。
    ///   - faceRestoration: 是否启用人脸还原。
    ///   - generationVideoFormat: 服务端生成规格；传入 `nil` 时使用本地媒体规格。
    ///   - paddingContain: 是否使用保留完整内容的填充方式，并以显示尺寸计算交互坐标。
    ///   - ensureCurrent: 确认本次操作仍有效的回调。
    /// - Throws: 上下文缺失、条件更新失败或操作失效时抛出错误。
    func update(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        context: RealtimeContext?,
        faceRestoration: Bool = false,
        generationVideoFormat: RealtimeVideoFormat? = nil,
        paddingContain: Bool = false,
        ensureCurrent: RealtimeGenerationValidity = {}
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
            videoFormat: videoFormat,
            useDisplayedSize: paddingContain
        )
        try ensureCurrent()
        currentContext = resolvedContext
        currentFaceRestoration = faceRestoration
    }

    /// 停止当前交互并发送停止生成信令。
    ///
    /// - Parameter taskID: 需要停止的生成任务标识。
    /// - Throws: 停止生成信令发送失败时抛出错误。
    func stop(taskID: String) async throws {
        await interactionController.stopInteraction()
        try await streamController.stopGeneration(taskID: taskID)
    }

    /// 清除已缓存的生成条件，并停止当前生成与交互。
    ///
    /// - Parameter taskID: 需要停止的生成任务标识；没有任务时为空字符串。
    /// - Throws: 停止生成信令发送失败时抛出错误。
    func reset(taskID: String = "") async throws {
        currentContext = nil
        currentFaceRestoration = false
        try await stop(taskID: taskID)
    }

    /// 生成带有 iOS 平台标记的随机任务标识。
    ///
    /// - Returns: 格式为 `task-<22 位 URL 安全随机串>?os=ios` 的任务标识。
    nonisolated static func createTaskID() -> String {
        var uuid = UUID().uuid
        let data = withUnsafeBytes(of: &uuid) { Data($0) }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "task-\(encoded)?os=ios"
    }
}
