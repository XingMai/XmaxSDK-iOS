//
//  RoomEvent.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 生成 SDK 与 RTC 房间之间传输的结构化事件消息。
enum RoomEvent {

    /// 编码开始生成信令并附加运行环境。
    ///
    /// - Parameters:
    ///   - userID: 本地 RTC 用户账号。
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 当前生成条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否保留源比例并填充生成画布。
    /// - Returns: 可发送的 JSON 开始信令。
    /// - Throws: 生成参数、码率计算或 JSON 编码失败时抛出错误。
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

    /// 编码生成条件更新信令并附加运行环境。
    ///
    /// - Parameters:
    ///   - userID: 本地 RTC 用户账号。
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 当前生成条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否保留源比例并填充生成画布。
    /// - Returns: 可发送的 JSON 条件变更信令。
    /// - Throws: 生成参数或 JSON 编码失败时抛出错误。
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

    /// 编码回传尺寸和下行码率更新信令。
    ///
    /// - Parameters:
    ///   - userID: 本地 RTC 用户账号。
    ///   - taskID: 需要更新的生成任务标识。
    ///   - targetSize: 生成后返回的整数像素尺寸。
    /// - Returns: 可发送的 JSON 回传尺寸变更信令。
    /// - Throws: 目标尺寸无效、码率计算或 JSON 编码失败时抛出错误。
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

    /// 编码停止生成信令。
    ///
    /// - Parameters:
    ///   - userID: 本地 RTC 用户账号。
    ///   - taskID: 需要停止的生成任务标识。
    /// - Returns: 可发送的 JSON 停止信令。
    /// - Throws: JSON 编码失败时抛出错误。
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

    /// 编码生成任务的媒体归一化坐标轨迹。
    ///
    /// - Parameters:
    ///   - userID: 本地 RTC 用户账号。
    ///   - taskID: 接收轨迹的生成任务标识。
    ///   - points: 按采样顺序排列、相对于处理后媒体尺寸的 `[0, 1]` 坐标点。
    /// - Returns: 可发送的 JSON 轨迹信令。
    /// - Throws: 坐标或 JSON 编码失败时抛出错误。
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

    /// 编码房间心跳信令。
    ///
    /// - Parameter userID: 本地 RTC 用户账号。
    /// - Returns: 可发送的 JSON 心跳信令。
    /// - Throws: JSON 编码失败时抛出错误。
    static func heartbeat(
        userID: String
    ) throws -> String {
        try encode(HeartbeatPayload(userID: userID))
    }
}

private extension RoomEvent {

    /// 校验回传尺寸并计算下行码率预算。
    ///
    /// - Parameter size: 回传视频的整数像素尺寸。
    /// - Returns: 以 kbps 表示的下行最小和最大码率。
    /// - Throws: 尺寸无效或码率计算失败时抛出错误。
    static func downlinkBitrates(
        _ size: CGSize
    ) throws -> (minimum: Int, maximum: Int) {
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

    /// 统一附加运行环境和会话任务字段后编码信令。
    ///
    /// - Parameter payload: 具体业务事件的可编码载荷。
    /// - Returns: 键顺序稳定的 UTF-8 JSON 文本。
    /// - Throws: 载荷编码、JSON 转换或文本转换失败时抛出错误。
    static func encode(
        _ payload: some Encodable
    ) throws -> String {
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

    /// 在业务信令中附加运行环境信息。
    struct Envelope<Payload: Encodable>: Encodable {

        /// 需要封装运行信息的业务信令内容。
        let payload: Payload

        /// 发送信令时携带的客户端运行环境。
        let runtime: RuntimeInfo

        /// 将业务载荷及运行环境写入同一个编码容器。
        ///
        /// - Parameter encoder: 输出信令使用的编码器。
        /// - Throws: 业务载荷或运行环境编码失败时抛出错误。
        func encode(
            to encoder: Encoder
        ) throws {
            try payload.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(runtime, forKey: .runtime)
        }

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 客户端运行环境字段。
            case runtime
        }
    }

    /// 编码生成尺寸、参考条件和输出选项。
    struct GenerationParameters: Encodable {

        /// 生成信令中的模型占位值；具体模型由会话确定。
        let model = "default"

        /// 生成画布的宽高，单位为像素。
        let size: [Int]

        /// 生成结果回传的宽高，单位为像素。
        let targetSize: [Int]?

        /// 描述生成效果的提示词。
        let prompt: String

        /// 服务端可访问的参考图片地址。
        let referencePath: String?

        /// 是否镜像处理输入画面。
        let mirror: Bool?

        /// 是否启用人脸修复。
        let faceRestoration: Bool

        /// 输入内容适配生成画布的填充策略。
        let padding: String?

        /// 服务端视频编码码率下限，单位为 kbps。
        let minimumBitrate: Int?

        /// 服务端视频编码码率上限，单位为 kbps。
        let maximumBitrate: Int?

        /// 创建生成参数，并按需要附加下行码率配置。
        ///
        /// - Parameters:
        ///   - videoFormat: 服务端生成使用的视频规格。
        ///   - targetSize: 生成后回传尺寸；`nil` 表示保持生成尺寸。
        ///   - context: 参考图和提示词等生成条件。
        ///   - faceRestoration: 是否回贴原始人脸。
        ///   - paddingContain: 是否按包含模式填充画布。
        ///   - mirror: 可选镜像设置；非空时同时生成下行码率字段。
        /// - Throws: 需要计算下行码率时，尺寸或码率无效会抛出错误。
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

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 生成模型字段。
            case model

            /// 生成画布尺寸字段。
            case size

            /// 结果回传尺寸字段。
            case targetSize = "target_size"

            /// 生成提示词字段。
            case prompt

            /// 参考图片地址字段。
            case referencePath = "ref_image_path"

            /// 输入镜像标记字段。
            case mirror

            /// 人脸修复开关字段。
            case faceRestoration = "face_replace"

            /// 画布填充策略字段。
            case padding

            /// 编码码率下限字段。
            case minimumBitrate = "min_bitrate"

            /// 编码码率上限字段。
            case maximumBitrate = "max_bitrate"
        }
    }

    /// 表示开始生成的房间信令。
    struct StartPayload: Encodable {

        /// 启动生成的事件名称。
        let event = "start"

        /// 本次生成使用的尺寸、条件与画面配置。
        let params: GenerationParameters

        /// 发起生成的业务用户标识。
        let userID: String

        /// 本次生成任务标识。
        let taskID: String

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 信令事件名称字段。
            case event

            /// 信令业务参数字段。
            case params

            /// 业务用户标识字段。
            case userID = "user_id"

            /// 生成任务标识字段。
            case taskID = "uid"
        }
    }

    /// 表示更新生成条件的房间信令。
    struct ChangeConditionPayload: Encodable {

        /// 更新生成条件的事件名称。
        let event = "change_condition"

        /// 需要更新的生成条件与画面配置。
        let params: GenerationParameters

        /// 当前生成任务的业务用户标识。
        let userID: String

        /// 本次生成任务标识。
        let taskID: String

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 信令事件名称字段。
            case event

            /// 信令业务参数字段。
            case params

            /// 业务用户标识字段。
            case userID = "user_id"

            /// 生成任务标识字段。
            case taskID = "uid"
        }
    }

    /// 编码回传尺寸及对应的下行码率预算。
    struct TargetSizeParameters: Encodable {

        /// 生成结果回传的宽高，单位为像素。
        let targetSize: [Int]

        /// 服务端视频编码码率下限，单位为 kbps。
        let minimumBitrate: Int

        /// 服务端视频编码码率上限，单位为 kbps。
        let maximumBitrate: Int

        /// 校验并创建回传尺寸及码率参数。
        ///
        /// - Parameter size: 目标回传整数像素尺寸。
        /// - Throws: 尺寸校验或下行码率计算失败时抛出错误。
        init(
            size: CGSize
        ) throws {
            let budget = try RoomEvent.downlinkBitrates(size)
            targetSize = [Int(size.width), Int(size.height)]
            minimumBitrate = budget.minimum
            maximumBitrate = budget.maximum
        }

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 结果回传尺寸字段。
            case targetSize = "target_size"

            /// 编码码率下限字段。
            case minimumBitrate = "min_bitrate"

            /// 编码码率上限字段。
            case maximumBitrate = "max_bitrate"
        }
    }

    /// 表示动态调整回传尺寸的房间信令。
    struct ChangeTargetSizePayload: Encodable {

        /// 更新回传尺寸的事件名称。
        let event = "change_target_size"

        /// 新的回传尺寸及编码码率范围。
        let params: TargetSizeParameters

        /// 当前生成任务的业务用户标识。
        let userID: String

        /// 本次生成任务标识。
        let taskID: String

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 信令事件名称字段。
            case event

            /// 信令业务参数字段。
            case params

            /// 业务用户标识字段。
            case userID = "user_id"

            /// 生成任务标识字段。
            case taskID = "uid"
        }
    }

    /// 表示停止生成任务的房间信令。
    struct StopPayload: Encodable {

        /// 停止生成的事件名称。
        let event = "stop"

        /// 当前生成任务的业务用户标识。
        let userID: String

        /// 本次生成任务标识。
        let taskID: String

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 信令事件名称字段。
            case event

            /// 业务用户标识字段。
            case userID = "user_id"

            /// 生成任务标识字段。
            case taskID = "uid"
        }
    }

    /// 表示生成任务的媒体归一化坐标轨迹信令。
    struct TracksPayload: Encodable {

        /// 发送轨迹的事件名称。
        let event = "tracks"

        /// 相对于处理后完整媒体尺寸的归一化坐标，每项为 [x, y]。
        let tracks: [[Double]]

        /// 发送轨迹的业务用户标识。
        let userID: String

        /// 轨迹所属的生成任务标识。
        let taskID: String

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 信令事件名称字段。
            case event

            /// 归一化轨迹坐标字段。
            case tracks

            /// 业务用户标识字段。
            case userID = "user_id"

            /// 生成任务标识字段。
            case taskID = "uid"
        }
    }

    /// 表示保持房间活动的心跳信令。
    struct HeartbeatPayload: Encodable {

        /// 房间心跳的事件名称。
        let event = "heartbeat"

        /// 本次房间心跳的业务用户标识。
        let userID: String

        /// 映射服务端约定的信令字段名。
        enum CodingKeys: String, CodingKey {

            /// 信令事件名称字段。
            case event

            /// 业务用户标识字段。
            case userID = "user_id"
        }
    }
}
