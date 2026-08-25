/// 实时业务错误监听器。
public typealias RealtimeErrorListener = @MainActor @Sendable (
    XmaxError
) -> Void
