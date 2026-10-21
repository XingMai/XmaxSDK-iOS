//
//  XmaxLogger.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import OSLog

/// 控制 XmaxSDK 输出的日志类型。
public struct XmaxLoggerOption: OptionSet, Sendable {

    /// 日志类型对应的位掩码。
    public let rawValue: UInt

    /// 使用指定的位掩码创建日志选项。
    public init(
        rawValue: UInt
    ) {
        self.rawValue = rawValue
    }

    /// Room、API、Realtime、Storage 等业务运行日志。
    public static let business = Self(rawValue: 1 << 0)

    /// RTC 性能指标及性能告警日志。
    public static let performance = Self(rawValue: 1 << 1)

    /// 输出全部 XmaxSDK 日志。
    public static let all: Self = [.business, .performance]
}

/// 统一输出带 Xmax 前缀和类别的系统日志。
///
/// 调用方不得传入 API Key、Token、Secret、Authorization 或完整敏感响应。
struct XmaxLogger: Sendable {

    /// 实时连接与生成生命周期日志。
    static let realtime = Self(category: "Realtime")

    /// RTC 媒体传输日志。
    static let rtc = Self(category: "RTC")

    /// 媒体采集与处理日志。
    static let media = Self(category: "Media")

    /// HTTP API 请求日志。
    static let api = Self(category: "API")

    /// 对象存储日志。
    static let storage = Self(category: "Storage")

    /// 房间信令与心跳日志。
    static let room = Self(category: "Room")

    /// 流发布、订阅及质量调整日志。
    static let stream = Self(category: "Stream")

    /// 视频渲染日志。
    static let render = Self(category: "Render")

    /// 轨迹交互日志。
    static let interaction = Self(category: "Interaction")

    /// 系统权限日志。
    static let permission = Self(category: "Permission")

    /// 输出到日志前缀中的业务分类名称。
    private let category: String

    /// 保存全局日志选项和语言环境。
    private static let state = XmaxLoggerState()

    /// 输出到系统统一日志的底层记录器。
    private static let logger = Logger(
        subsystem: "ai.xmax.XmaxSDK",
        category: "XmaxSDK"
    )

    /// 创建使用指定分类前缀的日志入口。
    private init(
        category: String
    ) {
        self.category = category
    }

    /// 更新全局日志选项和细项语言，后一次配置覆盖前一次。
    ///
    /// - Parameters:
    ///   - options: 允许输出的日志类型。
    ///   - environment: 决定日志细项语言的服务环境。
    static func configure(
        options: XmaxLoggerOption,
        environment: XmaxEnvironment = .china
    ) {
        state.update(options, environment: environment)
    }

    /// 按当前环境选择日志细项语言。
    ///
    /// - Parameters:
    ///   - chinese: 国内环境使用的中文文案。
    ///   - english: 海外环境使用的英文文案。
    /// - Returns: 当前环境对应的文案。
    static func localized(
        _ chinese: String,
        _ english: String
    ) -> String {
        state.environment == .china ? chinese : english
    }

    /// 判断指定日志类型是否全部启用。
    ///
    /// - Parameter option: 需要检查的日志选项；空选项不启用。
    /// - Returns: 配置包含全部指定选项时返回 `true`。
    static func isEnabled(
        _ option: XmaxLoggerOption
    ) -> Bool {
        state.isEnabled(option)
    }

    /// 输出调试级别日志，仅在对应选项启用时构建消息。
    ///
    /// - Parameters:
    ///   - message: 需要输出的日志内容，延迟到实际输出时求值。
    ///   - option: 控制本条日志是否输出的选项。
    func debug(
        message: @autoclosure () -> String,
        option: XmaxLoggerOption = .business
    ) {
        write(
            level: .debug,
            message: message,
            option: option
        )
    }

    /// 输出信息级别日志，仅在对应选项启用时构建消息。
    ///
    /// - Parameters:
    ///   - message: 需要输出的日志内容，延迟到实际输出时求值。
    ///   - option: 控制本条日志是否输出的选项。
    func info(
        message: @autoclosure () -> String,
        option: XmaxLoggerOption = .business
    ) {
        write(
            level: .info,
            message: message,
            option: option
        )
    }

    /// 输出警告级别日志，仅在对应选项启用时构建消息。
    ///
    /// - Parameters:
    ///   - message: 需要输出的日志内容，延迟到实际输出时求值。
    ///   - option: 控制本条日志是否输出的选项。
    func warn(
        message: @autoclosure () -> String,
        option: XmaxLoggerOption = .business
    ) {
        write(
            level: .warning,
            message: message,
            option: option
        )
    }

    /// 输出错误级别日志，仅在对应选项启用时构建消息。
    ///
    /// - Parameters:
    ///   - message: 需要输出的日志内容，延迟到实际输出时求值。
    ///   - option: 控制本条日志是否输出的选项。
    func error(
        message: @autoclosure () -> String,
        option: XmaxLoggerOption = .business
    ) {
        write(
            level: .error,
            message: message,
            option: option
        )
    }

    /// 为每一行日志添加 SDK 和业务分类前缀。
    ///
    /// - Parameter message: 未添加前缀的日志内容。
    /// - Returns: 每行均具有统一分类前缀的日志文本。
    func formattedMessage(
        message: String
    ) -> String {
        let prefix = "[Xmax][\(category)]"

        return message
            .components(separatedBy: "\n")
            .map { "\(prefix) \($0)" }
            .joined(separator: "\n")
    }

    /// 检查输出选项并按指定级别写入系统日志。
    ///
    /// - Parameters:
    ///   - level: 本条日志的严重级别。
    ///   - message: 生成日志内容的闭包，仅在启用时调用。
    ///   - option: 控制输出的日志选项。
    private func write(
        level: Level,
        message: () -> String,
        option: XmaxLoggerOption
    ) {
        guard Self.state.isEnabled(option) else {
            return
        }

        let formatted = formattedMessage(
            message: message()
        )
        switch level {
        case .debug:
            Self.logger.debug("\(formatted, privacy: .public)")
        case .info:
            Self.logger.info("\(formatted, privacy: .public)")
        case .warning:
            Self.logger.warning("\(formatted, privacy: .public)")
        case .error:
            Self.logger.error("\(formatted, privacy: .public)")
        }
    }

    /// 区分日志在系统日志中的严重程度。
    private enum Level {

        /// 辅助定位问题的详细信息。
        case debug

        /// 正常业务流程信息。
        case info

        /// 可恢复异常或使用约束提示。
        case warning

        /// 操作失败信息。
        case error
    }
}

/// 以线程安全方式保存 SDK 全局日志配置。
final class XmaxLoggerState: @unchecked Sendable {

    /// 保护全局日志配置的读写。
    private let lock = NSLock()

    /// 当前启用的日志类型位掩码。
    private var options: XmaxLoggerOption = []

    /// 决定日志细项语言的运行环境。
    private var storedEnvironment: XmaxEnvironment = .china

    /// 线程安全读取的日志语言环境。
    var environment: XmaxEnvironment {
        lock.withLock { storedEnvironment }
    }

    /// 以线程安全方式更新全局日志配置。
    ///
    /// - Parameters:
    ///   - options: 允许输出的日志类型。
    ///   - environment: 决定细项语言的服务环境。
    func update(
        _ options: XmaxLoggerOption,
        environment: XmaxEnvironment = .china
    ) {
        lock.lock()
        self.options = options
        storedEnvironment = environment
        lock.unlock()
    }

    /// 判断指定日志类型是否全部启用。
    ///
    /// - Parameter option: 需要检查的日志选项；空选项不启用。
    /// - Returns: 配置包含全部指定选项时返回 `true`。
    func isEnabled(
        _ option: XmaxLoggerOption
    ) -> Bool {
        guard !option.isEmpty else {
            return false
        }

        lock.lock()
        let enabled = options.contains(option)
        lock.unlock()
        return enabled
    }
}
