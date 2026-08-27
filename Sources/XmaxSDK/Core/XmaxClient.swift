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
        XmaxLogger.configure(options: configuration.loggerOptions)
        apiService = ApiService(apiKey: configuration.apiKey)
    }

    init(
        configuration: XmaxConfiguration,
        apiService: any ApiServicing
    ) {
        self.configuration = configuration
        XmaxLogger.configure(options: configuration.loggerOptions)
        self.apiService = apiService
    }

    /// 创建实时媒体 Manager。
    ///
    /// 本地相机预览不依赖 API Key 校验；服务端连接能力接入后，相关操作再校验配置。
    ///
    /// - Parameter options: 实时生成模型等业务配置。
    /// - Returns: 可用于创建和控制本地相机流的实时 Manager。
    @MainActor
    public func createRealtimeManager(
        options: RealtimeConfiguration
    ) -> any XmaxRealtimeManaging {
        XmaxRealtimeManager(
            options: options,
            apiService: apiService
        )
    }

    /// 创建文件存储 Manager。
    ///
    /// - Returns: 可用于上传和下载媒体文件的存储 Manager。
    /// - Throws: SDK 全局配置无效时抛出 `XmaxError`。
    public func createStorageManager() throws -> any XmaxStorageManaging {
        try configuration.validate()
        return XmaxStorageManager(apiService: apiService)
    }

    /// 创建媒体处理与能力查询 Service。
    ///
    /// - Returns: 可用于计算模型输入尺寸和查询平台媒体能力的 Service。
    public func createMediaService() -> any MediaServicing {
        MediaService()
    }
}
