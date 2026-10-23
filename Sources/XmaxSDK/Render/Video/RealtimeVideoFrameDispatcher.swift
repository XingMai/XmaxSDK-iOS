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

/// Delivers final remote frames on a separate serial queue.
final class RealtimeVideoFrameDispatcher: @unchecked Sendable {

    /// The current listener and delivery revision.
    private struct State {

        /// The final frame listener for the active stream.
        var listener: RealtimeVideoFrameListener?

        /// The revision rejecting frames queued for a previous listener.
        var version = 0
    }

    /// The lock protecting the listener and revision.
    private let stateLock = NSLock()

    /// The synchronized listener state.
    private var state = State()

    /// The serial background delivery queue.
    private let deliveryQueue = DispatchQueue(
        label: "ai.xmax.sdk.remote-video-frame",
        qos: .userInitiated
    )

    /// Sets a final frame listener and invalidates previously queued callbacks.
    ///
    /// - Parameter listener: The final frame handler, or `nil` to stop callbacks.
    func setListener(
        _ listener: RealtimeVideoFrameListener?
    ) {
        stateLock.withLock {
            state.version += 1
            state.listener = listener
        }
    }

    /// Invalidates queued remote frames not yet delivered.
    func invalidatePendingFrames() {
        stateLock.withLock {
            state.version += 1
        }
    }

    /// Delivers final frames in order on a separate serial queue.
    ///
    /// - Parameter frame: The processed remote video frame.
    func dispatch(
        _ frame: RealtimeVideoFrame
    ) {
        let version = stateLock.withLock { () -> Int? in
            guard state.listener != nil else {
                return nil
            }
            return state.version
        }
        guard let version else {
            return
        }

        deliveryQueue.async { [weak self] in
            guard let listener = self?.listener(for: version) else {
                return
            }
            listener(frame)
        }
    }

    /// Returns the listener matching a delivery revision.
    ///
    /// - Parameter version: The revision recorded when the frame was queued.
    ///
    /// - Returns: The current listener, or `nil` if stale or removed.
    private func listener(
        for version: Int
    ) -> RealtimeVideoFrameListener? {
        stateLock.withLock {
            guard state.version == version else {
                return nil
            }
            return state.listener
        }
    }
}
