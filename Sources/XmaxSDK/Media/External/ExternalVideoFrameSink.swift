//
//  ExternalVideoFrameSink.swift
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

/// A serialized external frame sink that waits for in-flight submission on invalidation.
final class ExternalVideoFrameSink: RealtimeExternalFrameSink, @unchecked Sendable {

    /// The resolved media format used for preview and quality baselines.
    let videoFormat: RealtimeVideoFormat

    /// The source's declared input format.
    private let sourceVideoFormat: RealtimeVideoFormat

    /// The handler delivering frames to preview and RTC.
    private let frameListener: MediaVideoFrameListener

    /// The receiver for converted RTC audio packets, without local playback.
    private let audioFrameListener: MediaAudioFrameListener

    /// The unrecoverable failure handler for this binding.
    private let errorListener: XmaxErrorListener

    /// The lock serializing binding state, timestamps, and frame submission.
    private let lock = NSLock()

    /// Whether the binding accepts frames; failure or unbinding permanently invalidates it.
    private var active = true

    /// The last accepted timestamp, in microseconds.
    private var lastTimestampUs: Int64 = -1

    /// The optional audio converter, serialized with frame submission and invalidation.
    private var audioConverter: ExternalAudioFrameConverter?

    /// Creates a frame sink for a source binding.
    init(
        sourceVideoFormat: RealtimeVideoFormat,
        videoFormat: RealtimeVideoFormat,
        frameListener: @escaping MediaVideoFrameListener,
        hasAudio: Bool = false,
        audioFrameListener: @escaping MediaAudioFrameListener = { _ in
        },
        errorListener: @escaping XmaxErrorListener
    ) {
        self.sourceVideoFormat = sourceVideoFormat
        self.videoFormat = videoFormat
        self.frameListener = frameListener
        self.audioFrameListener = audioFrameListener
        audioConverter = hasAudio ? ExternalAudioFrameConverter() : nil
        self.errorListener = errorListener
    }

    /// Whether preview and generation frames are accepted.
    var isRequestingFrames: Bool {
        lock.withLock {
            active
        }
    }

    /// Copies and delivers a valid frame, ignoring invalid or nonincreasing timestamps.
    ///
    /// - Parameters:
    ///   - pixelBuffer: An upright buffer matching the declared source dimensions.
    ///   - timestamp: A strictly increasing monotonic timestamp.
    func pushVideo(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    ) {
        guard timestamp.isNumeric, timestamp.epoch == 0, timestamp >= .zero else {
            return
        }
        let converted = CMTimeConvertScale(
            timestamp,
            timescale: 1000000,
            method: .roundTowardZero
        )
        guard converted.isNumeric, converted.value >= 0 else {
            return
        }

        lock.withLock {
            guard active, converted.value > lastTimestampUs else {
                return
            }
            do {
                guard CVPixelBufferGetWidth(pixelBuffer) == sourceVideoFormat.width,
                    CVPixelBufferGetHeight(pixelBuffer) == sourceVideoFormat.height
                else {
                    throw XmaxError(
                        code: .mediaError,
                        message: "External frame dimensions must match source.videoFormat"
                    )
                }
                let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
                guard
                    pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                        || pixelFormat == kCVPixelFormatType_32BGRA
                else {
                    throw XmaxError(
                        code: .mediaError,
                        message: "External video requires NV12 video-range (420v) or BGRA pixels"
                    )
                }
                let frame = try VideoFrameConverter.convert(
                    pixelBuffer: pixelBuffer,
                    outputWidth: videoFormat.width,
                    outputHeight: videoFormat.height,
                    rotation: .rotation0,
                    timestampUs: converted.value
                )
                lastTimestampUs = converted.value
                try frameListener(frame)
            } catch {
                active = false
                errorListener(
                    XmaxError(
                        code: .mediaError,
                        message: "External video frame failed: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    /// Converts and submits PCM audio while the source binding accepts frames.
    ///
    /// - Parameter sampleBuffer: PCM samples timestamped on the source's video timeline.
    func pushAudio(
        _ sampleBuffer: CMSampleBuffer
    ) {
        lock.withLock {
            guard active, let audioConverter else {
                return
            }
            do {
                try audioConverter.append(
                    sampleBuffer,
                    handler: audioFrameListener
                )
            } catch {
                active = false
                self.audioConverter = nil
                errorListener(XmaxError.from(error))
            }
        }
    }

    /// Reports the binding's first unrecoverable failure.
    ///
    /// - Parameter error: The external capture or processing error.
    func reportError(
        _ error: any Error
    ) {
        lock.withLock {
            guard active else {
                return
            }
            active = false
            errorListener(
                XmaxError(
                    code: .mediaError,
                    message: "External video source failed: \(error.localizedDescription)"
                )
            )
        }
    }

    /// Waits for in-flight submission and rejects subsequent frames and failures.
    func invalidate() {
        lock.withLock {
            active = false
            audioConverter = nil
        }
    }
}
