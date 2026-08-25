import Foundation

/// 管理实时生成会话的创建、心跳维持和关闭。
final class RealtimeSessionService: RealtimeSessionServicing, @unchecked Sendable {

    // 服务层组件
    private let apiService: any ApiServicing
    private let heartbeatSleeper: RealtimeHeartbeatSleeper

    // 运行状态
    private let heartbeatLock = NSLock()
    private let heartbeatVersion = RealtimeHeartbeatVersion()
    private var heartbeatTask: Task<Void, Never>?

    /// 创建实时生成会话 Service。
    init(
        apiService: any ApiServicing,
        heartbeatSleeper: RealtimeHeartbeatSleeper = .live
    ) {
        self.apiService = apiService
        self.heartbeatSleeper = heartbeatSleeper
    }

    deinit {
        heartbeatVersion.advance()
        heartbeatTask?.cancel()
    }

    func createSession(model: RealtimeModel) async throws -> RealtimeSession {
        let payload = try await apiService.post(
            "/session",
            body: CreateSessionRequest(model: model.rawValue),
            as: SessionPayload.self
        )
        return try Self.makeSession(
            from: payload,
            requiresConnection: true
        )
    }

    func startHeartbeat(
        sessionID: String,
        onFailure: @escaping RealtimeSessionHeartbeatFailureHandler
    ) {
        heartbeatLock.withLock {
            let version = heartbeatVersion.advance()
            heartbeatTask?.cancel()

            let context = HeartbeatContext(
                apiService: apiService,
                sleeper: heartbeatSleeper,
                versionState: heartbeatVersion,
                version: version,
                sessionID: sessionID,
                onFailure: onFailure
            )
            heartbeatTask = Task {
                await Self.runHeartbeat(context)
            }
        }
    }

    func stopHeartbeat() {
        heartbeatLock.withLock {
            heartbeatVersion.advance()
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }

    func closeSession(sessionID: String) async throws {
        _ = try await apiService.delete(
            "/session/\(sessionID)",
            as: EmptyResponse.self
        )
    }
}

private extension RealtimeSessionService {
    struct CreateSessionRequest: Encodable, Sendable {
        let model: String
    }

    struct EmptyResponse: Decodable, Sendable {}

    struct HeartbeatContext: Sendable {
        let apiService: any ApiServicing
        let sleeper: RealtimeHeartbeatSleeper
        let versionState: RealtimeHeartbeatVersion
        let version: UInt64
        let sessionID: String
        let onFailure: RealtimeSessionHeartbeatFailureHandler
    }

    struct SessionPayload: Decodable, Sendable {
        let sessionUID: String?
        let userUID: String?
        let status: String?
        let modelExtra: ModelExtra?
        let closeReason: String?

        enum CodingKeys: String, CodingKey {
            case sessionUID = "sessionUid"
            case userUID = "userUid"
            case status
            case modelExtra
            case closeReason
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionUID = try? container.decode(
                String.self,
                forKey: .sessionUID
            )
            userUID = try? container.decode(String.self, forKey: .userUID)
            status = try? container.decode(String.self, forKey: .status)
            modelExtra = try? container.decode(
                ModelExtra.self,
                forKey: .modelExtra
            )
            closeReason = try? container.decode(
                String.self,
                forKey: .closeReason
            )
        }
    }

    enum ModelExtra: Decodable, Sendable {
        case object(ConnectionPayload)
        case json(String)
        case invalid

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let json = try? container.decode(String.self) {
                self = .json(json)
            } else if let payload = try? ConnectionPayload(from: decoder) {
                self = .object(payload)
            } else {
                self = .invalid
            }
        }
    }

    struct ConnectionPayload: Decodable, Sendable {
        let roomID: String?
        let token: String?
        let userID: String?
        let botName: String?

        enum CodingKeys: String, CodingKey {
            case roomID = "room_id"
            case token = "room_token"
            case userID = "user_id"
            case botName = "bot_name"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            roomID = try? container.decode(String.self, forKey: .roomID)
            token = try? container.decode(String.self, forKey: .token)
            userID = try? container.decode(String.self, forKey: .userID)
            botName = try? container.decode(String.self, forKey: .botName)
        }
    }

    static func runHeartbeat(_ context: HeartbeatContext) async {
        while context.versionState.isCurrent(context.version) {
            do {
                try await context.sleeper.sleep()
                try Task.checkCancellation()
                guard context.versionState.isCurrent(context.version) else {
                    return
                }

                let session = try await heartbeatSession(
                    sessionID: context.sessionID,
                    apiService: context.apiService
                )
                guard context.versionState.isCurrent(context.version) else {
                    return
                }
                try ensureSessionActive(session)
            } catch {
                guard context.versionState.invalidate(context.version) else {
                    return
                }
                await context.onFailure(
                    context.sessionID,
                    XmaxError.from(error)
                )
                return
            }
        }
    }

    static func heartbeatSession(
        sessionID: String,
        apiService: any ApiServicing
    ) async throws -> RealtimeSession {
        let payload = try await apiService.put(
            "/session/\(sessionID)/heartbeat",
            as: SessionPayload.self
        )
        return try makeSession(
            from: payload,
            requiresConnection: false
        )
    }

    static func ensureSessionActive(_ session: RealtimeSession) throws {
        guard let status = session.status, status != "ACTIVE" else {
            return
        }
        throw XmaxError(
            code: .sessionError,
            message: session.closeReason
                ?? "Session is no longer active: \(status)"
        )
    }

    static func makeSession(
        from payload: SessionPayload,
        requiresConnection: Bool
    ) throws -> RealtimeSession {
        guard let sessionID = nonEmpty(payload.sessionUID) else {
            throw XmaxError(
                code: .sessionError,
                message: "Invalid session response"
            )
        }

        let userID = nonEmpty(payload.userUID)
        let connection = makeConnection(
            from: payload.modelExtra,
            fallbackUserID: userID
        )
        if requiresConnection, connection == nil {
            throw XmaxError(
                code: .sessionError,
                message: "Session does not contain complete RTC join information"
            )
        }

        return RealtimeSession(
            id: sessionID,
            userID: userID,
            status: nonEmpty(payload.status),
            connection: connection,
            closeReason: nonEmpty(payload.closeReason)
        )
    }

    static func makeConnection(
        from modelExtra: ModelExtra?,
        fallbackUserID: String?
    ) -> RealtimeSessionConnection? {
        let payload: ConnectionPayload
        switch modelExtra {
        case .object(let value):
            payload = value
        case .json(let value):
            guard let data = value.data(using: .utf8),
                  let value = try? JSONDecoder().decode(
                      ConnectionPayload.self,
                      from: data
                  ) else {
                return nil
            }
            payload = value
        case .invalid, nil:
            return nil
        }

        guard let roomID = nonEmpty(payload.roomID),
              let token = nonEmpty(payload.token),
              let userID = nonEmpty(payload.userID) ?? fallbackUserID else {
            return nil
        }
        return RealtimeSessionConnection(
            roomID: roomID,
            userID: userID,
            token: token,
            botName: nonEmpty(payload.botName)
        )
    }

    static func nonEmpty(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized?.isEmpty == false ? normalized : nil
    }
}

/// 提供可替换的心跳等待行为，便于测试周期任务。
struct RealtimeHeartbeatSleeper: Sendable {
    let sleep: @Sendable () async throws -> Void

    static let live = RealtimeHeartbeatSleeper {
        try await Task.sleep(nanoseconds: 10_000_000_000)
    }
}

/// 使用版本号使已停止心跳的迟到结果失效。
private final class RealtimeHeartbeatVersion: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var value: UInt64 = 0

    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    func isCurrent(_ version: UInt64) -> Bool {
        lock.withLock { value == version }
    }

    func invalidate(_ version: UInt64) -> Bool {
        lock.withLock {
            guard value == version else {
                return false
            }
            value &+= 1
            return true
        }
    }
}
