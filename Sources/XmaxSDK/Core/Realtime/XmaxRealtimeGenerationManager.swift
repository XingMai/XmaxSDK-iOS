import Foundation

typealias RealtimeGenerationValidity = @Sendable () throws -> Void
typealias RealtimeGenerationStartedHandler = @Sendable () async throws -> Void

/// 协调生成信令、远端结果确认和条件更新。
actor XmaxRealtimeGenerationManager {

    // 业务层组件
    private let roomController: any RoomControlling
    private let streamController: any StreamControlling

    // 生成配置
    private let taskIDGenerator: @Sendable () -> String

    // 生成资源
    private var currentContext: RealtimeContext?

    // 运行状态
    private var conditionVersion = 0

    init(
        roomController: any RoomControlling,
        streamController: any StreamControlling,
        taskIDGenerator: @escaping @Sendable () -> String =
            XmaxRealtimeGenerationManager.createTaskID
    ) {
        self.roomController = roomController
        self.streamController = streamController
        self.taskIDGenerator = taskIDGenerator
    }

    func start(
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext?,
        ensureCurrent: @escaping RealtimeGenerationValidity,
        onGenerationStarted: @escaping RealtimeGenerationStartedHandler
    ) async throws -> String {
        guard let resolvedContext = context ?? currentContext else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "A realtime context is required for the first " +
                    "generation"
            )
        }

        let taskID = taskIDGenerator()
        let confirmation = try streamController.beginGeneration(
            taskID: taskID
        )
        conditionVersion = 0

        do {
            try await roomController.startGeneration(
                taskID: taskID,
                videoFormat: videoFormat,
                context: resolvedContext
            )
            try await onGenerationStarted()
            try await withTaskCancellationHandler {
                try await confirmation.value
            } onCancel: {
                confirmation.cancel()
            }
            try ensureCurrent()

            currentContext = resolvedContext
            return taskID
        } catch {
            await stop(taskID: taskID)
            throw XmaxError.from(error)
        }
    }

    func update(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext?
    ) async throws {
        guard let context else {
            return
        }

        conditionVersion += 1
        try await roomController.changeGenerationCondition(
            taskID: taskID,
            conditionVersion: conditionVersion,
            videoFormat: videoFormat,
            context: context
        )
        currentContext = context
    }

    func stop(taskID: String) async {
        let stoppedTaskID = await streamController.stopGeneration(
            taskID: taskID
        )
        await roomController.stopGeneration(taskID: stoppedTaskID)
    }

    func reset(taskID: String = "") async {
        currentContext = nil
        conditionVersion = 0
        await stop(taskID: taskID)
    }

    nonisolated static func createTaskID() -> String {
        var uuid = UUID().uuid
        let data = withUnsafeBytes(of: &uuid) { Data($0) }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "task-\(encoded)"
    }
}
