//
//  RealtimeSessionService.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

    /// 创建实时会话服务并配置周期心跳的等待策略。
    ///
    /// - Parameters:
    ///   - apiService: 发送会话请求的 API 服务。
    ///   - heartbeatSleeper: 控制心跳间隔的异步等待策略。
    init(
        apiService: any ApiServicing,
        heartbeatSleeper: RealtimeHeartbeatSleeper = .live
    ) {
        self.apiService = apiService
        self.heartbeatSleeper = heartbeatSleeper
    }

    /// 使当前心跳失效并取消尚未结束的周期任务。
    deinit {
        heartbeatVersion.advance()
        heartbeatTask?.cancel()
    }

    /// 创建指定模型的实时会话，解析用于 RTC 进房的连接信息。
    ///
    /// - Parameter model: 本次实时生成使用的模型。
    /// - Returns: 服务端创建的会话及其 RTC 连接信息。
    /// - Throws: 会话请求失败、响应缺失必要字段或任务取消时抛出错误。
    func createSession(model: RealtimeModel) async throws -> RealtimeSession {
        let payload = try await apiService.post(
            "/session",
            body: CreateSessionRequest(model: model.rawValue),
            as: SessionPayload.self
        )
        do {
            return try Self.makeSession(from: payload, requiresConnection: true)
        } catch {
            if let sessionID = Self.nonEmpty(payload.sessionUID) {
                do {
                    try await closeSession(sessionID: sessionID)
                } catch {
                    XmaxLogger.realtime.error(message: "关闭无效会话失败 (Failed to Close Invalid Session)\n└─ \(error.localizedDescription)")
                }
            }
            throw error
        }
    }

    /// 启动指定会话的周期心跳，并替换之前的心跳任务。
    ///
    /// - Parameters:
    ///   - sessionID: 需要保活的会话标识。
    ///   - onFailure: 心跳失败时接收会话标识和错误的回调。
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

    /// 停止当前心跳，并使其尚未处理的失败通知失效。
    func stopHeartbeat() {
        heartbeatLock.withLock {
            heartbeatVersion.advance()
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }

    /// 关闭指定服务端会话。
    ///
    /// - Parameter sessionID: 需要关闭的会话标识。
    /// - Throws: 关闭请求失败或任务取消时抛出错误。
    func closeSession(sessionID: String) async throws {
        do {
            _ = try await apiService.delete(
                "/session/\(sessionID)",
                as: EmptyResponse.self
            )
        } catch {
            throw XmaxError.from(error)
        }
    }
}

private extension RealtimeSessionService {
    /// 创建实时会话时提交的模型信息。
    struct CreateSessionRequest: Encodable, Sendable {

        // 会话创建参数
        let model: String
    }

    /// 接收不包含业务字段的成功响应。
    struct EmptyResponse: Decodable, Sendable {}

    /// 保存单次心跳循环的服务、会话和有效性信息。
    struct HeartbeatContext: Sendable {

        // 心跳执行组件
        let apiService: any ApiServicing
        let sleeper: RealtimeHeartbeatSleeper


        // 生命周期校验
        let versionState: RealtimeHeartbeatVersion
        let version: UInt64


        // 会话与回调
        let sessionID: String
        let onFailure: RealtimeSessionHeartbeatFailureHandler
    }

    /// 接收服务端会话字段，由业务层校验必要内容。
    struct SessionPayload: Decodable, Sendable {

        // 会话响应字段
        let sessionUID: String?
        let userUID: String?
        let status: String?
        let modelExtra: ModelExtra?
        let closeReason: String?

        /// 定义服务端字段与本地属性的解码映射。
        enum CodingKeys: String, CodingKey {
            case sessionUID = "sessionUid"
            case userUID = "userUid"
            case status
            case modelExtra
            case closeReason
        }

        /// 解码会话响应，无法解析的可选字段置为空。
        ///
        /// - Parameter decoder: 提供会话响应数据的解码器。
        /// - Throws: 无法创建字段解码容器时抛出解码错误。
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

    /// 接收对象或 JSON 字符串形式的 RTC 附加参数。
    enum ModelExtra: Decodable, Sendable {
        case object(ConnectionPayload)
        case json(String)
        case invalid

        /// 解码对象或 JSON 字符串形式的 RTC 连接附加信息。
        ///
        /// - Parameter decoder: 提供附加信息的解码器。
        /// - Throws: 无法创建单值解码容器时抛出解码错误。
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

    /// 接收 RTC 进房字段及应用标识。
    struct ConnectionPayload: Decodable, Sendable {

        // RTC 连接字段
        let roomID: String?
        let token: String?
        let userID: String?
        let botName: String?
        let appID: String?

        /// 定义服务端字段与本地属性的解码映射。
        enum CodingKeys: String, CodingKey {
            case roomID = "room_id"
            case token = "room_token"
            case userID = "rtc_user_id"
            case botName = "rtc_bot_id"
            case appID = "rtc_app_id"
        }

        /// 解码 RTC 连接参数，无法解析的可选字段置为空。
        ///
        /// - Parameter decoder: 提供 RTC 连接字段的解码器。
        /// - Throws: 无法创建字段解码容器时抛出解码错误。
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            roomID = try? container.decode(String.self, forKey: .roomID)
            token = try? container.decode(String.self, forKey: .token)
            userID = try? container.decode(String.self, forKey: .userID)
            botName = try? container.decode(String.self, forKey: .botName)
            appID = try? container.decode(String.self, forKey: .appID)
        }
    }

    /// 周期发送有效会话的心跳，首次有效故障后通知并结束循环。
    ///
    /// - Parameter context: 当前心跳的会话、等待策略与有效性信息。
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

    /// 发送一次会话心跳并解析最新状态。
    ///
    /// - Parameters:
    ///   - sessionID: 需要保活的会话标识。
    ///   - apiService: 发送心跳请求的 API 服务。
    /// - Returns: 服务端返回的最新会话状态。
    /// - Throws: 请求失败、响应无效或任务取消时抛出错误。
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

    /// 检查服务端是否明确结束了会话。
    ///
    /// - Parameter session: 需要检查状态的会话。
    /// - Throws: 会话状态非空且不为 `ACTIVE` 时抛出会话错误。
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

    /// 校验必要字段并将响应转换为实时会话。
    ///
    /// - Parameters:
    ///   - payload: 服务端返回的原始会话字段。
    ///   - requiresConnection: 是否必须包含完整且有效的 RTC 连接信息。
    /// - Returns: 经过字段规范化与有效性检查的会话。
    /// - Throws: 会话标识缺失或要求的 RTC 连接信息无效时抛出会话错误。
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
        let connection = makeConnection(from: payload.modelExtra)
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

    /// 解析 RTC 附加字段并校验其应用标识。
    ///
    /// - Parameter modelExtra: 对象或 JSON 字符串形式的 RTC 附加字段。
    /// - Returns: 完整且匹配当前 RTC 应用的连接参数；字段无效时返回 `nil`。
    static func makeConnection(
        from modelExtra: ModelExtra?
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
              let userID = nonEmpty(payload.userID),
              let botName = nonEmpty(payload.botName),
              nonEmpty(payload.appID) == RtcEngineManager.defaultAppID else {
            return nil
        }
        return RealtimeSessionConnection(
            roomID: roomID,
            userID: userID,
            token: token,
            botName: botName
        )
    }

    /// 去除字符串首尾空白并排除空内容。
    ///
    /// - Parameter value: 待规范化的可选字符串。
    /// - Returns: 非空的规范化字符串；没有有效内容时返回 `nil`。
    static func nonEmpty(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized?.isEmpty == false ? normalized : nil
    }
}

/// 封装每次心跳发送前的异步等待策略。
struct RealtimeHeartbeatSleeper: Sendable {

    // 等待策略
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

    /// 更新心跳版本，使此前的心跳结果失效。
    ///
    /// - Returns: 更新后的版本号。
    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    /// 判断心跳版本是否仍属于当前生命周期。
    ///
    /// - Parameter version: 待检查的心跳版本号。
    /// - Returns: 与当前版本一致时返回 `true`。
    func isCurrent(_ version: UInt64) -> Bool {
        lock.withLock { value == version }
    }

    /// 仅在版本仍有效时推进版本，使该心跳失效。
    ///
    /// - Parameter version: 需要失效的心跳版本号。
    /// - Returns: 成功使当前版本失效时返回 `true`；过期版本返回 `false`。
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
