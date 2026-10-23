//
//  RealtimeExternalVideoSource.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo

/// A video source that supplies frames captured, decoded, or processed by your app.
///
/// XmaxSDK uses the frames for local preview and realtime generation. Your app manages permissions,
/// capture devices, playback, and resource cleanup. This protocol supports video only and doesn't
/// capture microphone audio.
///
/// Lifecycle methods run on the main actor. You can submit frames from a capture or processing
/// queue.
@MainActor
public protocol RealtimeExternalVideoSource: AnyObject, Sendable {

    /// The source frame dimensions, frame rate, and encoding options.
    ///
    /// Keep this value unchanged until frame delivery stops.
    var videoFormat: RealtimeVideoFormat {
        get
    }

    /// Starts delivering video frames to the specified sink.
    ///
    /// Install your frame callback and return when the source is ready to deliver frames. You don't
    /// need to submit the first frame before returning or wait for generation to begin. Continue
    /// delivering frames while disconnected to keep the local preview running.
    ///
    /// Pace frames according to the source's `videoFormat`, with orientation and mirroring applied
    /// to the pixels. If startup fails or is cancelled, XmaxSDK calls `stop()` to end frame
    /// delivery.
    ///
    /// - Parameter sink: The receiver for frames from this source.
    ///
    /// - Throws: An error if the source can't start delivering frames.
    func start(
        sink: any RealtimeExternalFrameSink
    ) async throws

    /// Stops delivering frames and releases the source's reference to the sink.
    ///
    /// This method must be safe to call more than once. Your app retains ownership of its capture
    /// devices and players and decides when to release them.
    func stop() async
}

/// A receiver for video frames from a single source attachment.
///
/// The sink processes frames synchronously and discards further input after delivery stops or the
/// source fails. You can submit frames from any queue.
public protocol RealtimeExternalFrameSink: AnyObject, Sendable {

    /// The processed media format used for local preview and adaptive quality.
    ///
    /// XmaxSDK limits the pixel area to the model's maximum and aligns each dimension to a multiple
    /// of four. The source frame rate and encoding options are preserved. Submit frames at the
    /// source's dimensions; XmaxSDK resizes them to this format.
    var videoFormat: RealtimeVideoFormat {
        get
    }

    /// A Boolean value that indicates whether the sink accepts video frames.
    ///
    /// This value remains `true` while disconnected so frames can drive the local preview. It
    /// becomes `false` when the source is detached or fails.
    var isRequestingFrames: Bool {
        get
    }

    /// Submits a video frame for local preview and realtime generation.
    ///
    /// XmaxSDK copies or resizes the pixels before this method returns. You can reuse the buffer
    /// afterward, but must not modify it during submission. Invalid, duplicate, or decreasing
    /// timestamps are ignored.
    ///
    /// - Parameters:
    ///   - pixelBuffer: An upright NV12 video-range (`420v`) or BGRA buffer whose dimensions match
    ///     the source's `videoFormat`, with any required mirroring already applied.
    ///   - timestamp: A nonnegative, strictly increasing timestamp from a monotonic clock. Keep
    ///     timestamps increasing across seeks and playback loops.
    func pushVideo(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    )

    /// Reports a source failure that prevents further frame delivery.
    ///
    /// XmaxSDK ends the realtime connection and releases the local stream.
    ///
    /// - Parameter error: The unrecoverable capture, decoding, or processing error.
    func reportError(
        _ error: any Error
    )
}
