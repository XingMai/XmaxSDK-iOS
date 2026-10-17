//
//  XmaxClient.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// SDK 的统一入口，负责创建实时、存储和媒体服务组件。
public final class XmaxClient: Sendable {

    // SDK 配置
    /// 客户端使用的全局配置。
    public let configuration: XmaxConfiguration


    // 服务层组件
    private let apiService: any ApiServicing
    private let realtimeApiOverride: (any ApiServicing)?

    /// 创建 SDK 客户端。
    ///
    /// - Parameter configuration: SDK 全局配置。
    public init(configuration: XmaxConfiguration) {
        self.configuration = configuration
        realtimeApiOverride = nil
        XmaxLogger.configure(options: configuration.loggerOptions, environment: configuration.environment)
        apiService = ApiService(
            apiKey: configuration.apiKey,
            baseURL: configuration.environment.apiBaseURL
        )
    }

    /// 使用指定 API 服务创建 SDK 客户端。
    ///
    /// - Parameters:
    ///   - configuration: 客户端配置，同时决定全局日志选项和语言。
    ///   - apiService: 存储与实时会话共用的 API 服务。
    init(
        configuration: XmaxConfiguration,
        apiService: any ApiServicing
    ) {
        self.configuration = configuration
        XmaxLogger.configure(options: configuration.loggerOptions, environment: configuration.environment)
        self.apiService = apiService
        realtimeApiOverride = apiService
    }

    /// 创建管理本地媒体、实时连接和生成任务的组件。
    ///
    /// 创建组件和本地预览不校验 API Key；访问服务端时校验凭证。
    ///
    /// - Parameter options: 实时生成模型等业务配置。
    /// - Returns: 可用于管理摄像头、图片和视频输入及实时生成的组件。
    @MainActor
    public func createRealtimeManager(
        options: RealtimeConfiguration
    ) -> any XmaxRealtimeManaging {
        XmaxRealtimeManager(
            options: options,
            apiService: realtimeApiOverride ?? ApiService(
                apiKey: configuration.apiKey,
                baseURL: options.model.apiBaseURL
            )
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
    /// - Parameter model: 媒体输入规则使用的模型，默认为 `x2.1.1-preview-cn`。
    /// - Returns: 可用于计算模型输入尺寸和查询平台媒体能力的 Service。
    public func createMediaService(model: RealtimeModel = .x2_1_1_preview_cn) -> any MediaServicing {
        MediaService(model: model)
    }
}
