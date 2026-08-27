/// 创建实时 Manager 所需的业务配置。
public struct RealtimeConfiguration: Equatable, Sendable {

    /// 实时生成业务使用的模型。
    public let model: RealtimeModel

    /// 是否默认开启远端生成画面的插帧。
    public let isFrameInterpolationEnabled: Bool

    /// 创建实时业务配置。
    ///
    /// - Parameters:
    ///   - model: 实时生成业务使用的模型。
    ///   - isFrameInterpolationEnabled: 是否默认开启远端生成画面的插帧。
    public init(
        model: RealtimeModel,
        isFrameInterpolationEnabled: Bool = true
    ) {
        self.model = model
        self.isFrameInterpolationEnabled = isFrameInterpolationEnabled
    }
}
