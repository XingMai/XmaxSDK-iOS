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

/// The categories of logs emitted by XmaxSDK.
public struct XmaxLoggerOption: OptionSet, Sendable {

    /// The log option bitmask.
    public let rawValue: UInt

    /// Creates log options from a bitmask.
    public init(
        rawValue: UInt
    ) {
        self.rawValue = rawValue
    }

    /// Service, connection, media, and storage logs.
    public static let business = Self(rawValue: 1 << 0)

    /// RTC statistics and performance alarm logs.
    public static let performance = Self(rawValue: 1 << 1)

    /// All XmaxSDK log categories.
    public static let all: Self = [.business, .performance]
}

/// A logger with SDK and domain prefixes.
///
/// Do not log API keys, tokens, secrets, authorization headers, or sensitive responses.
struct XmaxLogger: Sendable {

    /// The language used for log details, independent of service environments.
    enum Language: Equatable, Sendable {

        /// Chinese log details.
        case chinese

        /// English log details.
        case english
    }

    // MARK: - Loggers

    /// Realtime lifecycle logs.
    static let realtime = Self(category: "Realtime")

    /// RTC transport logs.
    static let rtc = Self(category: "RTC")

    /// Media capture and processing logs.
    static let media = Self(category: "Media")

    /// HTTP API logs.
    static let api = Self(category: "API")

    /// Object storage logs.
    static let storage = Self(category: "Storage")

    /// Room signaling and heartbeat logs.
    static let room = Self(category: "Room")

    /// Stream publishing, subscription, and quality logs.
    static let stream = Self(category: "Stream")

    /// Video rendering logs.
    static let render = Self(category: "Render")

    /// Trajectory interaction logs.
    static let interaction = Self(category: "Interaction")

    /// System permission logs.
    static let permission = Self(category: "Permission")

    // MARK: - Configuration

    /// The domain name in the log prefix.
    private let category: String

    /// The shared log options and language.
    private static let state = XmaxLoggerState()

    /// The system log writer.
    private static let logger = Logger(
        subsystem: "ai.xmax.XmaxSDK",
        category: "XmaxSDK"
    )

    /// Creates a logger for a domain.
    private init(
        category: String
    ) {
        self.category = category
    }

    /// Replaces the global log options and detail language.
    ///
    /// - Parameters:
    ///   - options: The enabled log categories.
    ///   - language: The language used for log details.
    static func configure(
        options: XmaxLoggerOption,
        language: Language = .chinese
    ) {
        state.update(
            options,
            language: language
        )
    }

    /// Selects log detail text for the configured language.
    ///
    /// - Parameters:
    ///   - chinese: The Chinese text.
    ///   - english: The English text.
    ///
    /// - Returns: The text for the configured language.
    static func localized(
        _ chinese: String,
        _ english: String
    ) -> String {
        state.language == .chinese ? chinese : english
    }

    /// Checks whether all specified log options are enabled.
    ///
    /// - Parameter option: The options to check. An empty set is disabled.
    ///
    /// - Returns: `true` if all specified options are enabled.
    static func isEnabled(
        _ option: XmaxLoggerOption
    ) -> Bool {
        state.isEnabled(option)
    }

    /// Logs a debug message when its category is enabled.
    ///
    /// - Parameters:
    ///   - message: The message, evaluated only when logging is enabled.
    ///   - option: The option controlling whether this message is logged.
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

    /// Logs an informational message when its category is enabled.
    ///
    /// - Parameters:
    ///   - message: The message, evaluated only when logging is enabled.
    ///   - option: The option controlling whether this message is logged.
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

    /// Logs a warning when its category is enabled.
    ///
    /// - Parameters:
    ///   - message: The message, evaluated only when logging is enabled.
    ///   - option: The option controlling whether this message is logged.
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

    /// Logs an error when its category is enabled.
    ///
    /// - Parameters:
    ///   - message: The message, evaluated only when logging is enabled.
    ///   - option: The option controlling whether this message is logged.
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

    /// Adds SDK and domain prefixes to each log line.
    ///
    /// - Parameter message: The unprefixed message.
    ///
    /// - Returns: The message with a domain prefix on every line.
    func formattedMessage(
        message: String
    ) -> String {
        let prefix = "[Xmax][\(category)]"

        return
            message
            .components(separatedBy: "\n")
            .map {
                "\(prefix) \($0)"
            }
            .joined(
                separator: "\n"
            )
    }

    /// Writes a message at the requested level when logging is enabled.
    ///
    /// - Parameters:
    ///   - level: The log severity.
    ///   - message: The message producer, called only when logging is enabled.
    ///   - option: The option controlling this log.
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

    /// A system log severity.
    private enum Level {

        /// Detailed diagnostic information.
        case debug

        /// Normal operation information.
        case info

        /// A recoverable issue or usage warning.
        case warning

        /// An operation failure.
        case error
    }
}

/// Thread-safe global logging configuration.
final class XmaxLoggerState: @unchecked Sendable {

    /// The lock protecting logging configuration.
    private let lock = NSLock()

    /// The enabled log option bitmask.
    private var options: XmaxLoggerOption = []

    /// The configured language for log details.
    private var storedLanguage: XmaxLogger.Language = .chinese

    /// The synchronized language for log details.
    var language: XmaxLogger.Language {
        lock.withLock {
            storedLanguage
        }
    }

    /// Updates the global logging configuration.
    ///
    /// - Parameters:
    ///   - options: The enabled log categories.
    ///   - language: The language used for log details.
    func update(
        _ options: XmaxLoggerOption,
        language: XmaxLogger.Language = .chinese
    ) {
        lock.lock()
        self.options = options
        storedLanguage = language
        lock.unlock()
    }

    /// Checks whether all specified log options are enabled.
    ///
    /// - Parameter option: The options to check. An empty set is disabled.
    ///
    /// - Returns: `true` if all specified options are enabled.
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
