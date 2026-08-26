import Foundation

typealias InteractionListener = @Sendable (
    _ taskID: String,
    _ points: [RealtimePoint]
) async throws -> Void

/// 将渲染容器中的交互行为转换为模型输入坐标并发送。
actor InteractionController: InteractionControlling {
    private struct ActiveInteraction {
        let taskID: String
        let videoFormat: RealtimeVideoFormat
    }

    // 交互事件监听
    private let listener: InteractionListener

    // 交互资源
    private var activeInteraction: ActiveInteraction?
    private var pendingPoints: [RealtimePoint]?
    private var drainTask: Task<Void, Never>?
    private var drainGeneration = 0

    init(listener: @escaping InteractionListener = { _, _ in }) {
        self.listener = listener
    }

    deinit {
        drainTask?.cancel()
    }

    func startInteraction(
        taskID: String,
        videoFormat: RealtimeVideoFormat
    ) {
        cancelPendingFrames()
        activeInteraction = ActiveInteraction(
            taskID: taskID,
            videoFormat: videoFormat
        )
    }

    func stopInteraction() {
        activeInteraction = nil
        cancelPendingFrames()
    }

    func submitInteraction(_ frame: InteractionFrame) {
        guard let activeInteraction,
              !frame.points.isEmpty else {
            return
        }

        let videoSize = activeInteraction.videoFormat.size
        let points = frame.points.compactMap {
            InteractionCoordinateMapper.map(
                $0,
                viewportSize: frame.viewportSize,
                videoSize: videoSize,
                contentMode: frame.contentMode
            )
        }
        guard !points.isEmpty else { return }

        pendingPoints = points
        guard drainTask == nil else { return }
        let generation = drainGeneration
        drainTask = Task { [weak self] in
            await self?.drainPendingFrames(generation: generation)
        }
    }
}

private extension InteractionController {
    func cancelPendingFrames() {
        drainGeneration += 1
        pendingPoints = nil
        drainTask?.cancel()
        drainTask = nil
    }

    func drainPendingFrames(generation: Int) async {
        while !Task.isCancelled,
              generation == drainGeneration,
              let interaction = activeInteraction,
              let points = pendingPoints {
            pendingPoints = nil
            do {
                try await listener(interaction.taskID, points)
            } catch is CancellationError {
                break
            } catch {
                XmaxLogger.warn(
                    "发送交互轨迹失败，已丢弃当前采样帧\n└─ 原因：" +
                        (error as NSError).localizedDescription,
                    category: "Interaction"
                )
            }
        }
        guard generation == drainGeneration else { return }
        drainTask = nil

        if activeInteraction != nil, pendingPoints != nil {
            drainTask = Task { [weak self] in
                await self?.drainPendingFrames(generation: generation)
            }
        }
    }
}
