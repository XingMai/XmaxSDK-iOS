import Foundation
import OSLog

/// 控制 XmaxSDK 输出的日志类型。
public struct XmaxLoggerOption: OptionSet, Sendable {

    /// 日志类型对应的位掩码。
    public let rawValue: UInt

    /// 使用指定的位掩码创建日志选项。
    ///
    /// - Parameter rawValue: 日志类型对应的位掩码。
    public init(rawValue: UInt) {
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

    private init(category: String) {
        self.category = category
    }

    /// 更新 SDK 全局日志选项和细项语言，后一次配置覆盖前一次。
    static func configure(
        options: XmaxLoggerOption,
        environment: XmaxEnvironment = .china
    ) {
        state.update(options, environment: environment)
    }

    /// 选择日志细项文案；日志标题保持原有中英双语。
    static func localized(_ chinese: String, _ english: String) -> String {
        state.environment == .china ? chinese : english
    }

    static func isEnabled(_ option: XmaxLoggerOption) -> Bool {
        state.isEnabled(option)
    }

    /// 输出调试日志。
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

    /// 输出普通信息日志。
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

    /// 输出警告日志。
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

    /// 输出错误日志。
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

    /// 为日志的每一行添加统一前缀。
    func formattedMessage(message: String) -> String {
        let prefix = "[Xmax][\(category)]"

        return message
            .components(separatedBy: "\n")
            .map { "\(prefix) \($0)" }
            .joined(separator: "\n")
    }

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

    private enum Level {
        case debug
        case info
        case warning
        case error
    }
}

/// 以线程安全方式保存 SDK 全局日志配置。
final class XmaxLoggerState: @unchecked Sendable {

    private let lock = NSLock()
    private var options: XmaxLoggerOption = []
    private var storedEnvironment: XmaxEnvironment = .china

    var environment: XmaxEnvironment {
        lock.withLock { storedEnvironment }
    }

    func update(
        _ options: XmaxLoggerOption,
        environment: XmaxEnvironment = .china
    ) {
        lock.lock()
        self.options = options
        storedEnvironment = environment
        lock.unlock()
    }

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
