import Foundation

/// SDK 全局配置。
public struct XmaxConfiguration: Equatable, Sendable {

    /// 调用 Xmax 服务使用的 API Key。
    public let apiKey: String

    /// SDK 输出的日志类型；默认为不输出日志。
    public let loggerOptions: XmaxLoggerOption

    /// 创建 SDK 全局配置。
    ///
    /// - Parameters:
    ///   - apiKey: 调用 Xmax 服务使用的 API Key。
    ///   - loggerOptions: SDK 输出的日志类型；默认为空。
    public init(
        apiKey: String,
        loggerOptions: XmaxLoggerOption = []
    ) {
        let resolvedApiKey = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.apiKey = resolvedApiKey
        self.loggerOptions = loggerOptions
    }

    /// 校验全局配置。
    ///
    /// - Throws: API Key 为空时抛出 `XmaxError`。
    public func validate() throws {
        guard !apiKey.isEmpty else {
            throw XmaxError(
                code: .invalidAPIKey,
                message: "API key cannot be empty"
            )
        }
    }
}
