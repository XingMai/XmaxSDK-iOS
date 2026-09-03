import Foundation

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

    func start(
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext?,
        ensureCurrent: @escaping RealtimeGenerationValidity
    ) async throws -> String {
        guard let resolvedContext = context ?? currentContext else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "A realtime context is required for the first " +
                    "generation"
            )
        }

        let taskID = taskIDGenerator()
        let confirmation = try await streamController.beginGeneration(
            taskID: taskID,
            videoFormat: videoFormat,
            context: resolvedContext
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
            currentContext = resolvedContext
            return taskID
        } catch {
            try? await stop(taskID: taskID)
            throw XmaxError.from(error)
        }
    }

    func update(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext?
    ) async throws {
        await interactionController.startInteraction(
            taskID: taskID,
            videoFormat: videoFormat
        )
        guard let context else {
            return
        }

        try await streamController.updateGeneration(
            taskID: taskID,
            videoFormat: videoFormat,
            context: context
        )
        currentContext = context
    }

    func stop(taskID: String) async throws {
        await interactionController.stopInteraction()
        try await streamController.stopGeneration(taskID: taskID)
    }

    func reset(taskID: String = "") async throws {
        currentContext = nil
        try await stop(taskID: taskID)
    }

    nonisolated static func createTaskID() -> String {
        var uuid = UUID().uuid
        let data = withUnsafeBytes(of: &uuid) { Data($0) }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "task-ios-\(encoded)"
    }
}
