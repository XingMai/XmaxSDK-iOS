/// 当前实时流程无法继续时触发的致命错误监听器。
public typealias RealtimeErrorListener = @MainActor @Sendable (
    XmaxError
) -> Void
