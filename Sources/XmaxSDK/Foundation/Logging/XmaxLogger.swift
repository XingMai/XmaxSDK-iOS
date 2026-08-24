import Foundation
import OSLog

/// 统一输出带 Xmax 前缀和类别的系统日志。
///
/// 调用方不得传入 API Key、Token、Secret、Authorization 或完整敏感响应。
enum XmaxLogger {
    private static let logger = Logger(
        subsystem: "ai.xmax.XmaxSDK",
        category: "XmaxSDK"
    )

    /// 输出调试日志。
    static func debug(_ message: String, category: String? = nil) {
        let formatted = formattedMessage(message, category: category)
        logger.debug("\(formatted, privacy: .public)")
    }

    /// 输出普通信息日志。
    static func info(_ message: String, category: String? = nil) {
        let formatted = formattedMessage(message, category: category)
        logger.info("\(formatted, privacy: .public)")
    }

    /// 输出警告日志。
    static func warn(_ message: String, category: String? = nil) {
        let formatted = formattedMessage(message, category: category)
        logger.warning("\(formatted, privacy: .public)")
    }

    /// 输出错误日志。
    static func error(_ message: String, category: String? = nil) {
        let formatted = formattedMessage(message, category: category)
        logger.error("\(formatted, privacy: .public)")
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
}
