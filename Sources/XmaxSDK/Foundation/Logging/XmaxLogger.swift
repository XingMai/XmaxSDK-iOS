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
enum XmaxLogger {

    // 日志配置
    private static let state = XmaxLoggerState()

    // 平台资源
    private static let logger = Logger(
        subsystem: "ai.xmax.XmaxSDK",
        category: "XmaxSDK"
    )

    /// 更新 SDK 全局日志选项。
    static func configure(options: XmaxLoggerOption) {
        state.update(options)
    }

    /// 输出调试日志。
    static func debug(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        option: XmaxLoggerOption = .business
    ) {
        write(
            level: .debug,
            message: message,
            category: category,
            option: option
        )
    }

    /// 输出普通信息日志。
    static func info(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        option: XmaxLoggerOption = .business
    ) {
        write(
            level: .info,
            message: message,
            category: category,
            option: option
        )
    }

    /// 输出警告日志。
    static func warn(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        option: XmaxLoggerOption = .business
    ) {
        write(
            level: .warning,
            message: message,
            category: category,
            option: option
        )
    }

    /// 输出错误日志。
    static func error(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        option: XmaxLoggerOption = .business
    ) {
        write(
            level: .error,
            message: message,
            category: category,
            option: option
        )
    }

    /// 为日志的每一行添加统一前缀。
    static func formattedMessage(_ message: String, category: String? = nil) -> String {
        let normalizedCategory = category?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix: String
        if let normalizedCategory, !normalizedCategory.isEmpty {
            prefix = "[Xmax][\(normalizedCategory)]"
        } else {
            prefix = "[Xmax]"
        }

        return message
            .components(separatedBy: "\n")
            .map { "\(prefix) \($0)" }
            .joined(separator: "\n")
    }

    private static func write(
        level: Level,
        message: () -> String,
        category: String?,
        option: XmaxLoggerOption
    ) {
        guard state.isEnabled(option) else {
            return
        }

        let formatted = formattedMessage(message(), category: category)
        switch level {
        case .debug:
            logger.debug("\(formatted, privacy: .public)")
        case .info:
            logger.info("\(formatted, privacy: .public)")
        case .warning:
            logger.warning("\(formatted, privacy: .public)")
        case .error:
            logger.error("\(formatted, privacy: .public)")
        }
    }

    private enum Level {
        case debug
        case info
        case warning
        case error
    }
}

/// 以线程安全方式保存 SDK 全局日志选项。
final class XmaxLoggerState: @unchecked Sendable {

    private let lock = NSLock()
    private var options: XmaxLoggerOption = []

    func update(_ options: XmaxLoggerOption) {
        lock.lock()
        self.options = options
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
