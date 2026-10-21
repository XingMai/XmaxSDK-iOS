//
//  RealtimeVideoFrameDispatcher.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 在独立串行队列中向接入方分发远端最终视频帧。
final class RealtimeVideoFrameDispatcher: @unchecked Sendable {

    /// 保存当前帧监听器及待交付帧的有效版本。
    private struct State {

        /// 接收当前有效输出流的最终视频帧。
        var listener: RealtimeVideoFrameListener?

        /// 监听器版本，用于过滤更换监听器前排队的帧。
        var version = 0
    }

    /// 保护帧监听器及其版本。
    private let stateLock = NSLock()

    /// 受锁保护的帧监听与有效期状态。
    private var state = State()

    /// 串行交付视频帧的后台队列。
    private let deliveryQueue = DispatchQueue(
        label: "ai.xmax.sdk.remote-video-frame",
        qos: .userInitiated
    )

    /// 设置最终视频帧监听器，并使旧监听器排队帧失效。
    ///
    /// - Parameter listener: 接收最终视频帧的回调；传入 `nil` 停止回调。
    func setListener(
        _ listener: RealtimeVideoFrameListener?
    ) {
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

    /// 按接收顺序在独立串行队列交付最终视频帧。
    ///
    /// - Parameter frame: 已完成插帧等处理的远端视频帧。
    func dispatch(
        _ frame: RealtimeVideoFrame
    ) {
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

    /// 读取与交付版本匹配的当前监听器。
    ///
    /// - Parameter version: 入队时记录的监听版本。
    /// - Returns: 仍有效的监听器；版本过期或监听已清除时返回 `nil`。
    private func listener(
        for version: Int
    ) -> RealtimeVideoFrameListener? {
        stateLock.withLock {
            guard state.version == version else { return nil }
            return state.listener
        }
    }
}
