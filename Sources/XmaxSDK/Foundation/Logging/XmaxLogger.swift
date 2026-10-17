//
//  XmaxLogger.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import OSLog

/// 控制 XmaxSDK 输出的日志类型。
public struct XmaxLoggerOption: OptionSet, Sendable {

    // 选项标识
    /// 日志类型对应的位掩码。
    public let rawValue: UInt

    /// 使用指定的位掩码创建日志选项。
    ///
    /// - Parameter rawValue: 日志类型对应的位掩码。
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    // 预定义日志选项
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

    // 分类日志
    static let realtime = Self(category: "Realtime")
    static let rtc = Self(category: "RTC")
    static let media = Self(category: "Media")
    static let api = Self(category: "API")
    static let storage = Self(category: "Storage")
    static let room = Self(category: "Room")
    static let stream = Self(category: "Stream")
    static let render = Self(category: "Render")
    static let interaction = Self(category: "Interaction")
    static let permission = Self(category: "Permission")

    // 日志类别
    private let category: String

    // 日志配置
    private static let state = XmaxLoggerState()

    // 平台资源
    private static let logger = Logger(
        subsystem: "ai.xmax.XmaxSDK",
        category: "XmaxSDK"
    )

    /// 创建使用指定分类前缀的日志入口。
    ///
    /// - Parameter category: 输出到日志前缀中的业务分类名称。
    private init(category: String) {
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
    static func localized(_ chinese: String, _ english: String) -> String {
        state.environment == .china ? chinese : english
    }

    /// 判断指定日志类型是否全部启用。
    ///
    /// - Parameter option: 需要检查的日志选项；空选项不启用。
    /// - Returns: 配置包含全部指定选项时返回 `true`。
    static func isEnabled(_ option: XmaxLoggerOption) -> Bool {
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
    func formattedMessage(message: String) -> String {
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
        case debug
        case info
        case warning
        case error
    }
}

/// 以线程安全方式保存 SDK 全局日志配置。
final class XmaxLoggerState: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 日志配置
    private var options: XmaxLoggerOption = []
    private var storedEnvironment: XmaxEnvironment = .china

    // 当前语言环境
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
    func isEnabled(_ option: XmaxLoggerOption) -> Bool {
        guard !option.isEmpty else {
            return false
        }

        lock.lock()
        let enabled = options.contains(option)
        lock.unlock()
        return enabled
    }
}
