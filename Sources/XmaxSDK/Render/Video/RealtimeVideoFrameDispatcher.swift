import Foundation

/// 在独立串行队列中向接入方分发远端最终视频帧。
final class RealtimeVideoFrameDispatcher: @unchecked Sendable {

    private struct State {
        var listener: RealtimeVideoFrameListener?
        var version = 0
    }

    // 监听状态
    private let stateLock = NSLock()
    private var state = State()

    // 分发资源
    private let deliveryQueue = DispatchQueue(
        label: "ai.xmax.sdk.remote-video-frame",
        qos: .userInitiated
    )

    /// 设置监听器并使已经排队的旧监听器帧失效。
    func setListener(_ listener: RealtimeVideoFrameListener?) {
        stateLock.withLock {
            state.version += 1
            state.listener = listener
        }
    }

    /// 使当前已经排队、但尚未交付的远端帧失效。
    func invalidatePendingFrames() {
        stateLock.withLock {
            state.version += 1
        }
    }

    /// 按接收顺序异步分发一帧，不阻塞渲染线程。
    func dispatch(_ frame: RealtimeVideoFrame) {
        let version = stateLock.withLock { () -> Int? in
            guard state.listener != nil else { return nil }
            return state.version
        }
        guard let version else { return }

        deliveryQueue.async { [weak self] in
            guard let listener = self?.listener(for: version) else {
                return
            }
            listener(frame)
        }
    }

    private func listener(
        for version: Int
    ) -> RealtimeVideoFrameListener? {
        stateLock.withLock {
            guard state.version == version else { return nil }
            return state.listener
        }
    }
}
