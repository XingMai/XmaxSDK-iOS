//
//  RoomController.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 管理 RTC 房间生命周期、心跳和实时生成信令。
actor RoomController: RoomControlling {

    /// 基础层组件
    private let rtcManager: any RtcManaging

    /// 传输层组件
    private let heartbeat: RoomHeartbeat

    /// 耗时统计
    private let timing: RealtimeTiming

    /// 房间资源
    private var state = State.idle
    private var leaveOperation: LeaveOperation?

    /// 创建房间控制器及默认心跳组件。
    ///
    /// - Parameters:
    ///   - rtcManager: 底层 RTC 管理器。
    ///   - timing: 共享的实时启动耗时记录器。
    init(
        rtcManager: any RtcManaging,
        timing: RealtimeTiming = RealtimeTiming()
    ) {
        self.rtcManager = rtcManager
        heartbeat = RoomHeartbeat(rtcManager: rtcManager)
        self.timing = timing
    }

    /// 使用指定心跳组件创建房间控制器。
    ///
    /// - Parameters:
    ///   - rtcManager: 底层 RTC 管理器。
    ///   - heartbeat: 维护房间周期信令的心跳组件。
    ///   - timing: 共享的实时启动耗时记录器。
    init(
        rtcManager: any RtcManaging,
        heartbeat: RoomHeartbeat,
        timing: RealtimeTiming = RealtimeTiming()
    ) {
        self.rtcManager = rtcManager
        self.heartbeat = heartbeat
        self.timing = timing
    }

    /// 加入实时房间，并在异步边界确认连接操作仍有效。
    ///
    /// - Parameters:
    ///   - connection: 服务端分配的 RTC 连接信息。
    ///   - ensureActive: 检查当前连接操作有效性的回调。
    /// - Throws: 房间状态无效、RTC 进房失败、超时或操作取消时抛出错误。
    func join(
        connection: RealtimeSessionConnection,
        ensureActive: @escaping @Sendable () throws -> Void
    ) async throws {
        do {
            try ensureActive()
        } catch {
            throw XmaxError.from(error)
        }
        guard case .idle = state, leaveOperation == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Leave the current RTC room before joining another one"
            )
        }

        let operationID = UUID()
        state = .joining(id: operationID)
        heartbeat.stop()

        do {
            timing.beginRoomJoin()
            try await rtcManager.joinRoom(
                configuration: RoomJoinConfiguration(
                    roomID: connection.roomID,
                    userID: connection.userID,
                    token: connection.token
                )
            )
            timing.finishRoomJoin()
            try ensureActive()
            guard case .joining(let currentID) = state,
                  currentID == operationID,
                  leaveOperation == nil else {
                throw XmaxError(
                    code: .cancelled,
                    message: "RTC room join was cancelled"
                )
            }

            state = .joined(userID: connection.userID)
            heartbeat.start(userID: connection.userID)
        } catch {
            if case .joining(let currentID) = state,
               currentID == operationID,
               leaveOperation == nil {
                state = .leaving
                heartbeat.stop()
                await rtcManager.leaveRoom()
                if case .leaving = state {
                    state = .idle
                }
            }
            throw XmaxError.from(error)
        }
    }

    /// 停止房间心跳并离开当前 RTC 房间。
    func leave() async {
        if let leaveOperation {
            await leaveOperation.task.value
            return
        }
        guard state.hasRoomResources else {
            return
        }

        let operationID = UUID()
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performLeave(operationID: operationID)
        }
        leaveOperation = LeaveOperation(id: operationID, task: task)
        await task.value
    }

    /// 将生成开始信令提交到房间发送队列。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 当前生成条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否保留源比例并填充生成画布。
    /// - Throws: 房间未就绪、信令编码或入队失败时抛出错误。
    func startGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        context: RealtimeContext,
        faceRestoration: Bool = false,
        paddingContain: Bool = false
    ) throws {
        try send(
            RoomEvent.start(
                userID: try requireUserID(),
                taskID: taskID,
                videoFormat: videoFormat,
                targetSize: targetSize,
                context: context,
                faceRestoration: faceRestoration,
                paddingContain: paddingContain
            )
        )
    }

    /// 将生成条件变更信令提交到房间发送队列。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 当前生成条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否保留源比例并填充生成画布。
    /// - Throws: 房间未就绪、调用取消、信令编码或入队失败时抛出错误。
    func changeGenerationCondition(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        context: RealtimeContext,
        faceRestoration: Bool = false,
        paddingContain: Bool = false
    ) throws {
        try Task.checkCancellation()
        try send(
            RoomEvent.changeCondition(
                userID: try requireUserID(),
                taskID: taskID,
                videoFormat: videoFormat,
                targetSize: targetSize,
                context: context,
                faceRestoration: faceRestoration,
                paddingContain: paddingContain
            )
        )
    }

    /// 调整当前生成任务的回传尺寸。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - targetSize: 生成后回传的整数像素尺寸。
    ///   - ensureActive: 发送前确认当前配置操作仍有效。
    /// - Throws: 操作已取消、房间未就绪或信令发送失败时抛出错误。
    func changeTargetSize(
        taskID: String,
        targetSize: CGSize,
        ensureActive: @Sendable () throws -> Void
    ) async throws {
        try ensureActive()
        let sending = try send(
            RoomEvent.changeTargetSize(
                userID: try requireUserID(),
                taskID: taskID,
                targetSize: targetSize
            ),
            reportFailure: false
        )
        try await RtcMessageQueue.waitForCompletion(of: sending)
    }

    /// 提交生成停止信令，未进房或任务为空时忽略。
    ///
    /// - Parameter taskID: 需要停止的生成任务标识。
    /// - Throws: 停止信令编码或入队失败时抛出错误。
    func stopGeneration(taskID: String) throws {
        guard !taskID.isEmpty,
              case .joined(let userID) = state else {
            return
        }

        try send(
            RoomEvent.stop(
                userID: userID,
                taskID: taskID
            )
        )
    }

    /// 提交当前生成任务的交互轨迹。
    ///
    /// - Parameters:
    ///   - taskID: 接收轨迹的任务标识；空值时不发送。
    ///   - points: 媒体归一化坐标点，取值范围为 `[0, 1]`；空数组时不发送。
    /// - Throws: 房间未就绪、轨迹编码或信令入队失败时抛出错误。
    func sendTracks(
        taskID: String,
        points: [RealtimePoint]
    ) throws {
        guard !taskID.isEmpty, !points.isEmpty else {
            return
        }

        try send(
            RoomEvent.tracks(
                userID: try requireUserID(),
                taskID: taskID,
                points: points
            )
        )
    }
}

private extension RoomController {
    /// 表示房间连接及离开流程所处阶段。
    enum State {
        case idle
        case joining(id: UUID)
        case joined(userID: String)
        case leaving

        /// 资源状态
        var hasRoomResources: Bool {
            switch self {
            case .idle, .leaving:
                false
            case .joining, .joined:
                true
            }
        }
    }

    /// 记录可由重复离房调用共同等待的清理任务。
    struct LeaveOperation {

        /// 操作标识
        let id: UUID

        /// 离房任务
        let task: Task<Void, Never>
    }

    /// 停止房间心跳并完成当前离房操作。
    ///
    /// - Parameter operationID: 用于核对离房任务有效性的操作标识。
    func performLeave(operationID: UUID) async {
        state = .idle
        heartbeat.stop()
        await rtcManager.leaveRoom()

        if leaveOperation?.id == operationID {
            leaveOperation = nil
        }
    }

    /// 提交统一房间信令并记录格式化日志。
    ///
    /// - Parameters:
    ///   - message: 完整 JSON 房间信令。
    ///   - reportFailure: 异步发送失败时是否通知 RTC 故障回调。
    /// - Returns: 本条信令的发送任务。
    /// - Throws: 信令提交失败时抛出 SDK 错误。
    @discardableResult
    func send(_ message: String, reportFailure: Bool = true) throws -> Task<Void, any Error> {
        let sending: Task<Void, any Error>
        do {
            sending = try rtcManager.sendRoomMessage(message, reportFailure: reportFailure)
        } catch {
            throw XmaxError.from(error)
        }
        XmaxLogger.room.debug(
            message: formatSignalLog(message)
        )
        return sending
    }

    /// 将房间信令格式化为可读的发送日志。
    ///
    /// - Parameter message: 原始房间信令文本。
    /// - Returns: 包含事件类型和 JSON 正文的日志；无法解析时保留原文。
    func formatSignalLog(_ message: String) -> String {
        guard let data = message.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let event = object as? [String: Any],
              let formattedData = try? JSONSerialization.data(
                  withJSONObject: event,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let formattedMessage = String(
                  data: formattedData,
                  encoding: .utf8
              ) else {
            return "发送房间信令 (Outbound Room Signaling)\n└─ \(XmaxLogger.localized("内容：", "Content: "))\(message)"
        }

        let eventType = event["event"] as? String ?? "unknown"
        let indentedMessage = formattedMessage.replacingOccurrences(
            of: "\n",
            with: "\n   "
        )
        return "发送房间信令 (Outbound Room Signaling)\n" +
            "├─ \(XmaxLogger.localized("类型：", "Type: "))\(eventType)\n" +
            "└─ \(XmaxLogger.localized("内容：", "Content: "))\n" +
            "   \(indentedMessage)"
    }

    /// 获取已连接房间的本地用户标识。
    ///
    /// - Returns: 本地 RTC 用户账号。
    /// - Throws: 房间尚未连接时抛出错误。
    func requireUserID() throws -> String {
        guard case .joined(let userID) = state else {
            throw XmaxError(
                code: .rtcError,
                message: "RTC room is not joined"
            )
        }
        return userID
    }
}
