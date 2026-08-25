/// SDK 的统一入口，负责创建实时、存储和媒体服务组件。
public final class XmaxClient: Sendable {

    // SDK 配置
    /// 客户端使用的全局配置。
    public let configuration: XmaxConfiguration

    // 服务层组件
    private let apiService: any ApiServicing

    /// 创建 SDK 客户端。
    ///
    /// - Parameter configuration: SDK 全局配置。
    public init(configuration: XmaxConfiguration) {
        self.configuration = configuration
        apiService = ApiService(apiKey: configuration.apiKey)
    }

    init(
        configuration: XmaxConfiguration,
        apiService: any ApiServicing
    ) {
        self.configuration = configuration
        self.apiService = apiService
    }

    /// 创建文件存储 Manager。
    ///
    /// - Returns: 可用于上传和下载媒体文件的存储 Manager。
    /// - Throws: SDK 全局配置无效时抛出 `XmaxError`。
    public func createStorageManager() throws -> any XmaxStorageManaging {
        try configuration.validate()
        return XmaxStorageManager(apiService: apiService)
    }
}
