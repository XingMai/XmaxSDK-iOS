//
//  RealtimeMediaFrameDispatcher.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo
import Foundation

/// Serializes bounded media delivery without blocking RTC audio or the render pipeline.
final class RealtimeMediaFrameDispatcher: @unchecked Sendable {

    /// Protects stream identity, timeline state, listener revisions, and queue admission.
    private let lock = NSLock()

    /// The background queue invoking application callbacks.
    private let queue: DispatchQueue

    /// The largest number of retained packets, including a callback currently running.
    private let maximumPendingFrames: Int

    /// The largest retained media size, including a callback currently running.
    private let maximumPendingBytes: Int

    /// The current application callback.
    private var listener: RealtimeMediaFrameListener?

    /// The revision rejecting output queued for a removed or replaced listener.
    private var version: UInt64 = 0

    /// The binding token shared by current audio and video producers.
    private var streamID: UUID?

    /// The sample-based audio rendering timeline.
    private var audioTimeline = RemoteAudioTimeline()

    /// The previous video PTS, used to expose backward clock changes.
    private var lastVideoPTS: CMTime?

    /// The previous video dimensions and pixel format, used to expose encoding format changes.
    private var lastVideoFormat: [Int]?

    /// Whether the next admitted audio packet must report a discontinuity.
    private var audioDiscontinuous = true

    /// Whether the next admitted video frame must report a discontinuity.
    private var videoDiscontinuous = true

    /// The number of retained delivery operations across all revisions.
    private var pendingFrames = 0

    /// The media retained by delivery operations across all revisions.
    private var pendingBytes = 0

    /// Creates a bounded output queue.
    init(
        maximumPendingFrames: Int = 256,
        maximumPendingBytes: Int = 32 * 1_024 * 1_024,
        deliveryQueue: DispatchQueue = DispatchQueue(
            label: "ai.xmax.sdk.remote-media-frame",
            qos: .userInitiated
        )
    ) {
        self.maximumPendingFrames = maximumPendingFrames
        self.maximumPendingBytes = maximumPendingBytes
        queue = deliveryQueue
    }

    /// Whether an application currently requests audio and video output.
    var hasListener: Bool {
        lock.withLock { listener != nil }
    }

    /// Replaces the listener and rejects queued output from the previous listener.
    func setListener(
        _ listener: RealtimeMediaFrameListener?
    ) {
        lock.withLock {
            version &+= 1
            self.listener = listener
            resetTimeline()
        }
    }

    /// Starts a new binding, invalidating packets from all previous producers.
    ///
    /// - Parameter active: Whether a remote result stream is bound.
    /// - Returns: The new stream identity, or `nil` after unbinding.
    @discardableResult
    func setStream(
        active: Bool
    ) -> UUID? {
        lock.withLock {
            version &+= 1
            streamID = active ? UUID() : nil
            resetTimeline()
            return streamID
        }
    }

    /// Normalizes audio on the producer thread and enqueues only a current binding's packets.
    func dispatchAudio(
        _ frame: RtcRemoteAudioFrame,
        streamID: UUID
    ) {
        lock.withLock {
            guard self.streamID == streamID, listener != nil else { return }
            guard let resolved = audioTimeline.resolve(frame) else {
                audioDiscontinuous = true
                return
            }
            let output = RealtimeMediaFrame(
                streamID: streamID,
                isDiscontinuous: audioDiscontinuous || resolved.discontinuous,
                content: .audio(resolved.frame)
            )
            audioDiscontinuous = !enqueue(output, bytes: frame.data.count)
        }
    }

    /// Enqueues final processed video while preserving its native or interpolated PTS.
    func dispatchVideo(
        _ frame: RealtimeVideoFrame,
        streamID: UUID
    ) {
        lock.withLock {
            guard self.streamID == streamID, listener != nil else { return }
            guard frame.presentationTimeStamp.isNumeric else {
                videoDiscontinuous = true
                return
            }
            let backwards = lastVideoPTS.map { frame.presentationTimeStamp <= $0 } ?? false
            let format = [
                CVPixelBufferGetWidth(frame.pixelBuffer),
                CVPixelBufferGetHeight(frame.pixelBuffer),
                Int(CVPixelBufferGetPixelFormatType(frame.pixelBuffer))
            ]
            let formatChanged = lastVideoFormat.map { $0 != format } ?? false
            lastVideoPTS = frame.presentationTimeStamp
            lastVideoFormat = format
            let output = RealtimeMediaFrame(
                streamID: streamID,
                isDiscontinuous: videoDiscontinuous || backwards || formatChanged,
                content: .video(frame)
            )
            videoDiscontinuous = !enqueue(output, bytes: CVPixelBufferGetDataSize(frame.pixelBuffer))
        }
    }

    /// Resets both tracks without changing the binding identity. Requires `lock`.
    private func resetTimeline() {
        audioTimeline.reset()
        lastVideoPTS = nil
        lastVideoFormat = nil
        audioDiscontinuous = true
        videoDiscontinuous = true
    }

    /// Admits one bounded callback in producer order. Requires `lock`.
    private func enqueue(
        _ frame: RealtimeMediaFrame,
        bytes: Int
    ) -> Bool {
        guard pendingFrames < maximumPendingFrames,
              bytes <= maximumPendingBytes - pendingBytes
        else {
            return false
        }
        pendingFrames += 1
        pendingBytes += bytes
        let revision = version
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                lock.withLock {
                    pendingFrames -= 1
                    pendingBytes -= bytes
                }
            }
            let callback = lock.withLock {
                version == revision && streamID == frame.streamID ? listener : nil
            }
            if let callback {
                #if DEBUG
                RealtimeDebugCaptureBridge.shared.mediaOutput(frame)
                #endif
                callback(frame)
            }
        }
        return true
    }
}
