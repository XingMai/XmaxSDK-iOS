import Foundation

/// 管理 RTC 房间生命周期、心跳和实时生成信令。
actor RoomController: RoomControlling {

    // 基础层组件
    private let rtcProvider: any RtcProviding

    // 传输层组件
    private let heartbeat: RoomHeartbeat

    // 房间资源
    private var state = State.idle
    private var leaveOperation: LeaveOperation?

    init(rtcProvider: any RtcProviding) {
        self.rtcProvider = rtcProvider
        heartbeat = RoomHeartbeat(rtcProvider: rtcProvider)
    }

    init(
        rtcProvider: any RtcProviding,
        heartbeat: RoomHeartbeat
    ) {
        self.rtcProvider = rtcProvider
        self.heartbeat = heartbeat
    }

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
            try await rtcProvider.joinRoom(
                configuration: RoomJoinConfiguration(
                    roomID: connection.roomID,
                    userID: connection.userID,
                    token: connection.token
                )
            )
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
                await rtcProvider.leaveRoom()
                if case .leaving = state {
                    state = .idle
                }
            }
            throw XmaxError.from(error)
        }
    }

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

    func startGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) throws {
        try send(
            RoomEvent.start(
                userID: try requireUserID(),
                taskID: taskID,
                videoFormat: videoFormat,
                context: context
            )
        )
    }

    func changeGenerationCondition(
        taskID: String,
        conditionVersion: Int,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) throws {
        try send(
            RoomEvent.changeCondition(
                userID: try requireUserID(),
                taskID: taskID,
                conditionVersion: conditionVersion,
                videoFormat: videoFormat,
                context: context
            )
        )
    }

    func stopGeneration(taskID: String) {
        guard !taskID.isEmpty,
              case .joined(let userID) = state else {
            return
        }

        do {
            try send(
                RoomEvent.stop(
                    userID: userID,
                    taskID: taskID
                )
            )
        } catch {
            XmaxLogger.error(
                "发送生成停止消息失败\n└─ 原因：" +
                    (error as NSError).localizedDescription,
                category: "Room"
            )
        }
    }

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
    enum State {
        case idle
        case joining(id: UUID)
        case joined(userID: String)
        case leaving

        var hasRoomResources: Bool {
            switch self {
            case .idle, .leaving:
                false
            case .joining, .joined:
                true
            }
        }
    }

    struct LeaveOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    func performLeave(operationID: UUID) async {
        state = .idle
        heartbeat.stop()
        await rtcProvider.leaveRoom()

        if leaveOperation?.id == operationID {
            leaveOperation = nil
        }
    }

    func send(_ message: String) throws {
        try rtcProvider.sendRoomMessage(message)
        XmaxLogger.debug(
            formatSignalLog(message),
            category: "Room"
        )
    }

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
            return "发送房间信令\n└─ 内容：\(message)"
        }

        let eventType = event["event"] as? String ?? "unknown"
        let indentedMessage = formattedMessage.replacingOccurrences(
            of: "\n",
            with: "\n   "
        )
        return "发送房间信令\n" +
            "├─ 类型：\(eventType)\n" +
            "└─ 内容：\n" +
            "   \(indentedMessage)"
    }

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
