//
//  InteractionController.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 异步接收生成任务标识及其视频像素轨迹坐标。
typealias InteractionListener = @Sendable (
    _ taskID: String,
    _ points: [RealtimePoint]
) async throws -> Void

/// 将渲染容器中的触控位置转换为固定媒体基准的像素坐标并发送。
actor InteractionController: InteractionControlling {
    /// 保存当前生成任务的交互坐标映射配置。
    private struct ActiveInteraction {

        // 生成任务
        let taskID: String

        // 坐标映射规则
        let videoFormat: RealtimeVideoFormat
    }

    // 交互事件监听
    private let listener: InteractionListener

    // 交互资源
    private var activeInteraction: ActiveInteraction?
    private var pendingPoints: [RealtimePoint]?
    private var drainTask: Task<Void, Never>?
    private var drainGeneration = 0

    /// 创建将轨迹坐标交付给信令层的交互控制器。
    ///
    /// - Parameter listener: 接收任务标识及视频像素坐标的异步回调。
    init(listener: @escaping InteractionListener = { _, _ in }) {
        self.listener = listener
    }

    /// 取消尚未完成的轨迹发送任务。
    deinit {
        drainTask?.cancel()
    }

    /// 开始接收当前生成任务的触控轨迹。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 固定的本地媒体规格，作为发送轨迹的像素坐标基准。
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

    /// 停止接收轨迹并清理当前任务。
    func stopInteraction() {
        activeInteraction = nil
        cancelPendingFrames()
    }

    /// 提交触控轨迹。
    ///
    /// - Parameter frame: 当前视图中采集的轨迹及显示尺寸。
    func submitInteraction(_ frame: InteractionFrame) {
        guard let activeInteraction,
              !frame.points.isEmpty else {
            return
        }

        let mediaSize = activeInteraction.videoFormat.size
        let displayedVideoSize = frame.displayedVideoSize ?? mediaSize
        let points = frame.points.compactMap {
            InteractionCoordinateMapper.map(
                $0,
                viewportSize: frame.viewportSize,
                displayedVideoSize: displayedVideoSize,
                mediaSize: mediaSize,
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
    /// 使当前发送任务失效并清空待发送轨迹。
    func cancelPendingFrames() {
        drainGeneration += 1
        pendingPoints = nil
        drainTask?.cancel()
        drainTask = nil
    }

    /// 持续发送最新轨迹采样，并过滤已失效的发送循环。
    ///
    /// - Parameter generation: 当前发送循环的版本标识。
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
                XmaxLogger.interaction.warn(
                    message: "发送交互轨迹失败，已丢弃当前采样帧 " +
                        "(Failed to Send Interaction Trajectory; Current Sample Dropped)\n" +
                        "└─ \(XmaxLogger.localized("原因：", "Reason: "))" +
                        (error as NSError).localizedDescription
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
