import Foundation
import Darwin

/// 生成 SDK 与 RTC 房间之间传输的结构化事件消息。
enum RoomEvent {
    /// 描述 SDK 发送房间信令时的运行环境。
    struct Runtime: Encodable, Sendable {
        let platform: String
        let osVersion: String
        let sdkVersion: String
        let deviceModel: String

        static let current = Runtime(
            platform: "ios",
            osVersion: currentOSVersion(),
            sdkVersion: XmaxSDKInfo.version,
            deviceModel: currentDeviceModel()
        )

        enum CodingKeys: String, CodingKey {
            case platform
            case osVersion = "os_version"
            case sdkVersion = "sdk_version"
            case deviceModel = "device_model"
        }
    }

    static func start(
        userID: String,
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) throws -> String {
        try encode(
            StartPayload(
                params: GenerationParameters(
                    videoFormat: videoFormat,
                    context: context
                ),
                userID: userID,
                taskID: taskID
            )
        )
    }

    static func changeCondition(
        userID: String,
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) throws -> String {
        try encode(
            ChangeConditionPayload(
                params: GenerationParameters(
                    videoFormat: videoFormat,
                    context: context
                ),
                userID: userID,
                taskID: taskID
            )
        )
    }

    static func stop(
        userID: String,
        taskID: String
    ) throws -> String {
        try encode(
            StopPayload(
                userID: userID,
                taskID: taskID
            )
        )
    }

    static func tracks(
        userID: String,
        taskID: String,
        points: [RealtimePoint]
    ) throws -> String {
        try encode(
            TracksPayload(
                tracks: points.map { [$0.x, $0.y] },
                userID: userID,
                taskID: taskID
            )
        )
    }

    static func heartbeat(userID: String) throws -> String {
        try encode(HeartbeatPayload(userID: userID))
    }
}

private extension RoomEvent {
    static func encode(_ payload: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(
            Envelope(payload: payload, runtime: .current)
        )
        guard let message = String(data: data, encoding: .utf8) else {
            throw XmaxError(
                code: .internalError,
                message: "Failed to encode RTC room event"
            )
        }
        return message
    }

    struct Envelope<Payload: Encodable>: Encodable {
        let payload: Payload
        let runtime: Runtime

        func encode(to encoder: Encoder) throws {
            try payload.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(runtime, forKey: .runtime)
        }

        enum CodingKeys: String, CodingKey {
            case runtime
        }
    }

    struct GenerationParameters: Encodable {
        let model = "default"
        let size: [Int]
        let prompt: String
        let referencePath: String?

        init(
            videoFormat: RealtimeVideoFormat,
            context: RealtimeContext
        ) {
            size = [videoFormat.width, videoFormat.height]
            prompt = context.prompt
            referencePath = context.referencePath
        }

        enum CodingKeys: String, CodingKey {
            case model
            case size
            case prompt
            case referencePath = "ref_image_path"
        }
    }

    struct StartPayload: Encodable {
        let event = "start"
        let params: GenerationParameters
        let userID: String
        let taskID: String

        enum CodingKeys: String, CodingKey {
            case event
            case params
            case userID = "user_id"
            case taskID = "uid"
        }
    }

    struct ChangeConditionPayload: Encodable {
        let event = "change_condition"
        let params: GenerationParameters
        let userID: String
        let taskID: String

        enum CodingKeys: String, CodingKey {
            case event
            case params
            case userID = "user_id"
            case taskID = "uid"
        }
    }

    struct StopPayload: Encodable {
        let event = "stop"
        let userID: String
        let taskID: String

        enum CodingKeys: String, CodingKey {
            case event
            case userID = "user_id"
            case taskID = "uid"
        }
    }

    struct TracksPayload: Encodable {
        let event = "tracks"
        let tracks: [[Double]]
        let userID: String
        let taskID: String

        enum CodingKeys: String, CodingKey {
            case event
            case tracks
            case userID = "user_id"
            case taskID = "uid"
        }
    }

    struct HeartbeatPayload: Encodable {
        let event = "heartbeat"
        let userID: String

        enum CodingKeys: String, CodingKey {
            case event
            case userID = "user_id"
        }
    }
}

private extension RoomEvent.Runtime {
    static func currentOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var components = [
            String(version.majorVersion),
            String(version.minorVersion)
        ]
        if version.patchVersion > 0 {
            components.append(String(version.patchVersion))
        }
        return components.joined(separator: ".")
    }

    static func currentDeviceModel() -> String {
        if let simulatorModel = ProcessInfo.processInfo.environment[
            "SIMULATOR_MODEL_IDENTIFIER"
        ], !simulatorModel.isEmpty {
            return simulatorModel
        }

        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else {
            return "unknown"
        }
        let capacity = MemoryLayout.size(ofValue: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: capacity
            ) { String(cString: $0) }
        }
    }
}
