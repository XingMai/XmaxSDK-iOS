import Foundation

/// SDK 全局配置。
public struct XmaxConfiguration: Equatable, Sendable {

    /// 调用 Xmax 服务使用的 API Key。
    public let apiKey: String

    /// 创建 SDK 全局配置。
    ///
    /// - Parameter apiKey: 调用 Xmax 服务使用的 API Key。
    public init(apiKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
