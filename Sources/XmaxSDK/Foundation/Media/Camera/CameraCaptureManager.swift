//
//  CameraCaptureManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import Foundation

/// An AVFoundation video capturer with serialized device and frame operations.
final class CameraCaptureManager: NSObject, CameraCaptureManaging, @unchecked Sendable {

    /// Capture resources.

    /// The capture session.
    private let session = AVCaptureSession()

    /// The raw video output.
    private let output = AVCaptureVideoDataOutput()

    /// The queue serializing capture configuration and frame processing.
    private let captureQueue = DispatchQueue(
        label: "ai.xmax.sdk.camera",
        qos: .userInitiated
    )

    /// Capture configuration.

    /// The active camera input, accessed only on `captureQueue`.
    private var input: AVCaptureDeviceInput?

    /// The cropped and scaled frame format.
    private var videoFormat: VideoFormat?

    /// The requested capture frame rate, in frames per second.
    private var frameRate = 0

    /// The display orientation applied to captured frames.
    private var orientation: CameraOrientation = .portrait

    /// Frame and session events.

    /// The handler for oriented and scaled frames.
    private var frameListener: (@Sendable (VideoFrame) throws -> Void)?

    /// The handler for capture and frame processing failures.
    private var errorListener: XmaxErrorListener?

    /// The capture session notification observers.
    private var observers: [NSObjectProtocol] = []

    /// Frame delivery state.

    /// The most recent output timestamp, in microseconds.
    private var lastTimestampUs: Int64?

    /// Whether a frame processing failure has already been reported for this capture.
    private var hasReportedFrameError = false

    /// Starts capture with upright NV12 frames at the requested dimensions.
    ///
    /// - Parameters:
    ///   - videoFormat: The output pixel format and dimensions.
    ///   - frameRate: The capture frame rate.
    ///   - position: The camera position.
    ///   - frameListener: The frame handler, called on the capture queue.
    ///   - errorListener: The capture failure handler.
    ///
    /// - Throws: An error if the device or format is unavailable or capture cannot start.
    func start(
        videoFormat: VideoFormat,
        frameRate: Int,
        position: CameraPosition,
        frameListener: @escaping @Sendable (VideoFrame) throws -> Void,
        errorListener: @escaping XmaxErrorListener
    ) async throws {
        try Task.checkCancellation()

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            captureQueue.async { [self] in
                do {
                    guard self.videoFormat == nil else {
                        throw Self.cameraError("Camera capture is already running")
                    }
                    guard frameRate > 0, frameRate <= Int(Int32.max),
                        videoFormat.pixelFormat == .nv12,
                        videoFormat.width.isMultiple(of: 2), videoFormat.height.isMultiple(of: 2)
                    else {
                        throw Self.cameraError("Camera capture format is invalid")
                    }

                    self.videoFormat = videoFormat
                    self.frameRate = frameRate
                    orientation =
                        videoFormat.height >= videoFormat.width ? .portrait : .landscapeRight
                    self.frameListener = frameListener
                    self.errorListener = errorListener

                    session.automaticallyConfiguresApplicationAudioSession = false
                    session.automaticallyConfiguresCaptureDeviceForWideColor = false
                    session.beginConfiguration()

                    do {
                        session.sessionPreset = .inputPriority
                        try replaceInput(position: position)

                        guard session.canAddOutput(output) else {
                            throw Self.cameraError("Camera video output is unavailable")
                        }
                        session.addOutput(output)

                        guard
                            output.availableVideoPixelFormatTypes.contains(
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                            )
                        else {
                            throw Self.cameraError("Camera does not support NV12 video output")
                        }
                        output.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                        ]
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(
                            self,
                            queue: captureQueue
                        )
                        try configureConnection()
                    } catch {
                        session.commitConfiguration()
                        throw error
                    }
                    session.commitConfiguration()

                    observeSession()
                    session.startRunning()
                    guard session.isRunning else {
                        throw Self.cameraError("Camera capture failed to start")
                    }

                    continuation.resume()
                } catch {
                    stopCapture()
                    continuation.resume(
                        throwing: error as? XmaxError
                            ?? Self.cameraError(error.localizedDescription)
                    )
                }
            }
        }
    }

    /// Switches cameras while retaining output dimensions and frame rate.
    ///
    /// - Parameter position: The requested camera position.
    ///
    /// - Throws: An error if the camera is unavailable or switching fails.
    func switchCamera(
        to position: CameraPosition
    ) async throws {
        try Task.checkCancellation()

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            captureQueue.async { [self] in
                do {
                    guard videoFormat != nil else {
                        throw Self.cameraError("Camera capture is not running")
                    }

                    session.beginConfiguration()
                    defer {
                        session.commitConfiguration()
                    }

                    let previousInput = input
                    do {
                        try replaceInput(position: position)
                        try configureConnection()
                    } catch {
                        if let input {
                            session.removeInput(input)
                        }
                        input = nil

                        if let previousInput, session.canAddInput(previousInput) {
                            session.addInput(previousInput)
                            input = previousInput
                            try? configureConnection()
                        }

                        throw error
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(
                        throwing: error as? XmaxError
                            ?? Self.cameraError(error.localizedDescription)
                    )
                }
            }
        }
    }

    /// Updates output dimensions and capture frame rate without replacing the session.
    ///
    /// - Parameters:
    ///   - videoFormat: The new NV12 output dimensions.
    ///   - frameRate: The frame rate, which must be supported by the device.
    ///
    /// - Throws: An error if capture is inactive, the format is unsupported, or configuration
    ///   fails.
    func updateFormat(
        _ videoFormat: VideoFormat,
        frameRate: Int
    ) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            captureQueue.async { [self] in
                do {
                    guard self.videoFormat != nil, let device = input?.device else {
                        throw Self.cameraError("Camera capture is not running")
                    }
                    guard frameRate > 0, frameRate <= Int(Int32.max),
                        videoFormat.width > 0, videoFormat.height > 0,
                        videoFormat.width.isMultiple(of: 2), videoFormat.height.isMultiple(of: 2),
                        videoFormat.pixelFormat == .nv12
                    else {
                        throw Self.cameraError("Camera capture format is invalid")
                    }

                    if self.frameRate != frameRate {
                        let selected = try selectFormat(
                            device: device,
                            frameRate: frameRate
                        )
                        try device.lockForConfiguration()
                        defer {
                            device.unlockForConfiguration()
                        }
                        session.beginConfiguration()
                        device.activeFormat = selected
                        let duration = CMTime(
                            value: 1,
                            timescale: Int32(frameRate)
                        )
                        device.activeVideoMinFrameDuration = duration
                        device.activeVideoMaxFrameDuration = duration
                        device.automaticallyAdjustsVideoHDREnabled = false
                        device.isVideoHDREnabled = false
                        session.commitConfiguration()
                    }

                    self.frameRate = frameRate
                    self.videoFormat = videoFormat
                    continuation.resume()
                } catch {
                    continuation.resume(
                        throwing: error as? XmaxError
                            ?? Self.cameraError(error.localizedDescription)
                    )
                }
            }
        }
    }

    /// Stops capture and waits for pending frames before releasing the device.
    func stop() async {
        await withCheckedContinuation { continuation in
            captureQueue.async { [self] in
                stopCapture()
                continuation.resume()
            }
        }
    }

    /// Updates frame orientation and dimensions without changing capture frame rate.
    ///
    /// - Parameters:
    ///   - orientation: The window's interface orientation.
    ///   - videoFormat: The upright output dimensions and pixel format.
    ///
    /// - Throws: An error if capture has stopped.
    func updateOrientation(
        _ orientation: CameraOrientation,
        videoFormat: VideoFormat
    ) async throws {
        try Task.checkCancellation()

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            captureQueue.async { [self] in
                do {
                    guard self.videoFormat != nil else {
                        throw Self.cameraError("Camera capture is not running")
                    }
                    guard self.orientation != orientation || self.videoFormat != videoFormat else {
                        continuation.resume()
                        return
                    }

                    self.orientation = orientation
                    self.videoFormat = videoFormat
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension CameraCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Delivers an oriented, resized frame with a host-clock timestamp.
    ///
    /// - Parameters:
    ///   - output: The video capture output.
    ///   - sampleBuffer: The captured pixel buffer and timestamp.
    ///   - connection: The video capture connection.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let videoFormat, let frameListener,
            connection === self.output.connection(with: .video),
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        let captureClock: CMClock?
        if #available(iOS 15.4, *) {
            captureClock = session.synchronizationClock
        } else {
            captureClock = session.masterClock
        }

        guard let clock = captureClock else {
            return
        }

        let hostTime = CMSyncConvertTime(
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            from: clock,
            to: CMClockGetHostTimeClock()
        )
        guard hostTime.isNumeric else {
            return
        }

        let timestampUs = CMTimeConvertScale(
            hostTime,
            timescale: 1000000,
            method: .default
        ).value
        guard timestampUs >= 0,
            lastTimestampUs.map({
                timestampUs > $0
            }) ?? true
        else {
            return
        }
        lastTimestampUs = timestampUs

        do {
            let frame = try VideoFrameConverter.convert(
                pixelBuffer: pixelBuffer,
                outputWidth: videoFormat.width,
                outputHeight: videoFormat.height,
                rotation: orientation.frameRotation,
                timestampUs: timestampUs
            )
            try frameListener(frame)
        } catch {
            guard !hasReportedFrameError else {
                return
            }

            hasReportedFrameError = true
            XmaxLogger.media.error(
                message:
                    "摄像头帧处理失败 (Camera Frame Processing Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.localizedDescription)"
            )
        }
    }
}

private extension CameraCaptureManager {

    /// Replaces the camera input and applies a format supporting the requested frame rate.
    ///
    /// - Parameter position: The requested camera position.
    ///
    /// - Throws: An error if the camera or format is unavailable or configuration fails.
    func replaceInput(
        position: CameraPosition
    ) throws {
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: position == .front ? .front : .back
            )
        else {
            throw Self.cameraError("The requested camera is unavailable")
        }

        let selected = try selectFormat(
            device: device,
            frameRate: frameRate
        )

        let newInput = try AVCaptureDeviceInput(device: device)
        if let input {
            session.removeInput(input)
        }
        input = nil

        guard session.canAddInput(newInput) else {
            throw Self.cameraError("Failed to attach the requested camera")
        }
        session.addInput(newInput)
        input = newInput

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }

        device.activeFormat = selected
        let duration = CMTime(
            value: 1,
            timescale: Int32(frameRate)
        )
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.automaticallyAdjustsVideoHDREnabled = false
        device.isVideoHDREnabled = false

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    /// Selects a capture format at the requested frame rate, preferring 16:9 over 4:3.
    ///
    /// - Parameters:
    ///   - device: The camera device.
    ///   - frameRate: The requested capture frame rate.
    ///
    /// - Returns: A 16:9 format up to 1920 × 1080, or a 4:3 format up to 1920 × 1440.
    ///
    /// - Throws: An error if no compatible format exists.
    func selectFormat(
        device: AVCaptureDevice,
        frameRate: Int
    ) throws -> AVCaptureDevice.Format {
        let selected = device.formats.compactMap {
            format -> (
                format: AVCaptureDevice.Format, area: Int64, isWide: Bool
            )? in
            guard
                format.videoSupportedFrameRateRanges.contains(
                    where: {
                        $0.minFrameRate <= Double(frameRate) && Double(frameRate) <= $0.maxFrameRate
                    }
                )
            else {
                return nil
            }

            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let longSide = Int64(
                max(
                    dimensions.width,
                    dimensions.height
                )
            )
            let shortSide = Int64(
                min(
                    dimensions.width,
                    dimensions.height
                )
            )
            let isWide = longSide * 9 == shortSide * 16
            guard longSide > 0, shortSide > 0,
                longSide <= 1920, shortSide <= 1440,
                isWide || longSide * 3 == shortSide * 4
            else {
                return nil
            }

            return (format, longSide * shortSide, isWide)
        }.max { lhs, rhs in
            if lhs.isWide != rhs.isWide {
                return !lhs.isWide
            }

            return lhs.area < rhs.area
        }?.format

        guard let selected else {
            throw Self.cameraError(
                "The camera does not support a compatible 16:9 or 4:3 format at the requested frame rate"
            )
        }

        return selected
    }

    /// Configures a fixed capture orientation with automatic mirroring disabled.
    ///
    /// - Throws: An error if the capture connection or orientation is unavailable.
    func configureConnection() throws {
        guard let connection = output.connection(with: .video),
            connection.isVideoOrientationSupported
        else {
            throw Self.cameraError("Camera video orientation is unavailable")
        }

        // Capture remains portrait-based; the frame converter applies window rotation.
        connection.videoOrientation = .portrait
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// Observes capture failures and resumes after media service resets or interruptions.
    func observeSession() {
        let errorListener = errorListener
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                let message = error?.localizedDescription ?? "Camera capture failed"

                self?.captureQueue.async { [weak self] in
                    guard let self, videoFormat != nil else {
                        return
                    }

                    if error?.code == AVError.mediaServicesWereReset.rawValue {
                        session.startRunning()
                        if session.isRunning {
                            return
                        }
                    }
                    errorListener?(Self.cameraError(message))
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.captureQueue.async { [weak self] in
                    guard let self, videoFormat != nil, !session.isRunning else {
                        return
                    }

                    session.startRunning()
                    if !session.isRunning {
                        errorListener?(Self.cameraError("Camera capture failed to resume"))
                    }
                }
            }
        )
    }

    /// Releases capture inputs, outputs, observers, and frame handlers.
    func stopCapture() {
        frameListener = nil
        errorListener = nil
        videoFormat = nil

        output.setSampleBufferDelegate(
            nil,
            queue: nil
        )
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()

        session.stopRunning()
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        session.commitConfiguration()

        input = nil
        frameRate = 0
        lastTimestampUs = nil
        hasReportedFrameError = false
    }

    /// Creates a camera capture error.
    ///
    /// - Parameter message: The error description.
    ///
    /// - Returns: A media error with the specified description.
    static func cameraError(
        _ message: String
    ) -> XmaxError {
        XmaxError(
            code: .mediaError,
            message: message
        )
    }
}
