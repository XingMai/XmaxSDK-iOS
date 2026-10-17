import Foundation

/// 生成 SDK 与 RTC 房间之间传输的结构化事件消息。
enum RoomEvent {
    static func start(
        userID: String,
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize? = nil,
        context: RealtimeContext,
        faceRestoration: Bool = false,
        paddingContain: Bool = false
    ) throws -> String {
        try encode(
            StartPayload(
                params: GenerationParameters(
                    videoFormat: videoFormat,
                    targetSize: targetSize,
                    context: context,
                    faceRestoration: faceRestoration,
                    paddingContain: paddingContain,
                    mirror: false
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
        targetSize: CGSize? = nil,
        context: RealtimeContext,
        faceRestoration: Bool = false,
        paddingContain: Bool = false
    ) throws -> String {
        try encode(
            ChangeConditionPayload(
                params: GenerationParameters(
                    videoFormat: videoFormat,
                    targetSize: targetSize,
                    context: context,
                    faceRestoration: faceRestoration,
                    paddingContain: paddingContain
                ),
                userID: userID,
                taskID: taskID
            )
        )
    }

    static func changeTargetSize(
        userID: String,
        taskID: String,
        targetSize: CGSize
    ) throws -> String {
        try encode(
            ChangeTargetSizePayload(
                params: TargetSizeParameters(size: targetSize),
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
    static func downlinkBitrates(_ size: CGSize) throws -> (minimum: Int, maximum: Int) {
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 2, size.height >= 2,
              size.width < CGFloat(Int.max), size.height < CGFloat(Int.max),
              size.width.rounded(.down) == size.width,
              size.height.rounded(.down) == size.height else {
            throw XmaxError(code: .invalidConfiguration, message: "Invalid return video dimensions")
        }
        let budget = try EncodingBitratePolicy.resolve(RealtimeVideoFormat(
            width: Int(size.width), height: Int(size.height), fps: 24
        ))
        return (100, min(10000, budget.maximum))
    }

    static func encode(_ payload: some Encodable) throws -> String {
        let payloadData = try JSONEncoder().encode(
            Envelope(payload: payload, runtime: .current)
        )
        guard var object = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw XmaxError(code: .internalError, message: "Failed to encode RTC room event")
        }
        if let taskID = object["uid"] {
            object["session_uid"] = taskID
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
        let runtime: RuntimeInfo

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
        let targetSize: [Int]?
        let prompt: String
        let referencePath: String?
        let mirror: Bool?
        let faceRestoration: Bool
        let padding: String?
        let minimumBitrate: Int?
        let maximumBitrate: Int?

        init(
            videoFormat: RealtimeVideoFormat,
            targetSize: CGSize?,
            context: RealtimeContext,
            faceRestoration: Bool,
            paddingContain: Bool = false,
            mirror: Bool? = nil
        ) throws {
            size = [videoFormat.width, videoFormat.height]
            self.targetSize = targetSize.map { [Int($0.width), Int($0.height)] }
            prompt = context.prompt
            referencePath = context.referencePath
            self.mirror = mirror
            self.faceRestoration = faceRestoration
            padding = paddingContain ? "contain" : nil
            if mirror != nil {
                let budget = try RoomEvent.downlinkBitrates(targetSize ?? videoFormat.size)
                minimumBitrate = budget.minimum
                maximumBitrate = budget.maximum
            } else {
                minimumBitrate = nil
                maximumBitrate = nil
            }
        }

        enum CodingKeys: String, CodingKey {
            case model
            case size
            case targetSize = "target_size"
            case prompt
            case referencePath = "ref_image_path"
            case mirror
            case faceRestoration = "face_replace"
            case padding
            case minimumBitrate = "min_bitrate"
            case maximumBitrate = "max_bitrate"
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

    struct TargetSizeParameters: Encodable {
        let targetSize: [Int]
        let minimumBitrate: Int
        let maximumBitrate: Int

        init(size: CGSize) throws {
            let budget = try RoomEvent.downlinkBitrates(size)
            targetSize = [Int(size.width), Int(size.height)]
            minimumBitrate = budget.minimum
            maximumBitrate = budget.maximum
        }

        enum CodingKeys: String, CodingKey {
            case targetSize = "target_size"
            case minimumBitrate = "min_bitrate"
            case maximumBitrate = "max_bitrate"
        }
    }

    struct ChangeTargetSizePayload: Encodable {
        let event = "change_target_size"
        let params: TargetSizeParameters
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
