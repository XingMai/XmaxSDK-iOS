/// SDK 的统一入口，后续负责创建实时、存储和媒体服务组件。
public final class XmaxClient: Sendable {

    /// 客户端使用的全局配置。
    public let configuration: XmaxConfiguration

    /// 创建 SDK 客户端。
    ///
    /// - Parameter configuration: SDK 全局配置。
    public init(configuration: XmaxConfiguration) {
        self.configuration = configuration
    }
}
