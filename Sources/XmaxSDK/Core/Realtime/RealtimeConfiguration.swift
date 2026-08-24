/// 创建实时 Manager 所需的业务配置。
public struct RealtimeConfiguration: Equatable, Sendable {

    /// 实时生成业务使用的模型。
    public let model: RealtimeModel

    /// 创建实时业务配置。
    ///
    /// - Parameter model: 实时生成业务使用的模型。
    public init(model: RealtimeModel) {
        self.model = model
    }
}
