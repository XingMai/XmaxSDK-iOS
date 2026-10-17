//
//  CameraCaptureManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import Foundation

/// 使用 AVFoundation 采集视频；设备操作和帧处理由同一串行队列管理。
final class CameraCaptureManager: NSObject, CameraCaptureManaging, @unchecked Sendable {

    // 平台资源
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "ai.xmax.sdk.camera", qos: .userInitiated)


    // 采集配置（仅在 captureQueue 访问）
    private var input: AVCaptureDeviceInput?
    private var videoFormat: VideoFormat?
    private var frameRate = 0
    private var orientation: CameraOrientation = .portrait


    // 事件监听
    private var frameListener: (@Sendable (VideoFrame) throws -> Void)?
    private var errorListener: XmaxErrorListener?
    private var observers: [NSObjectProtocol] = []


    // 运行状态
    private var lastTimestampUs: Int64?
    private var hasReportedFrameError = false

    /// 启动摄像头，输出已经转正并调整到目标尺寸的 NV12 帧。
    ///
    /// - Parameters:
    ///   - videoFormat: 输出像素格式和尺寸。
    ///   - frameRate: 采集帧率。
    ///   - position: 摄像头位置。
    ///   - frameListener: 在采集串行队列接收视频帧。
    ///   - errorListener: 接收采集运行错误。
    /// - Throws: 设备、规格或采集启动失败时抛出错误。
    func start(
        videoFormat: VideoFormat,
        frameRate: Int,
        position: CameraPosition,
        frameListener: @escaping @Sendable (VideoFrame) throws -> Void,
        errorListener: @escaping XmaxErrorListener
    ) async throws {
        try Task.checkCancellation()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            captureQueue.async { [self] in
                do {
                    guard self.videoFormat == nil else {
                        throw Self.cameraError("Camera capture is already running")
                    }
                    guard frameRate > 0, frameRate <= Int(Int32.max),
                          videoFormat.pixelFormat == .nv12,
                          videoFormat.width.isMultiple(of: 2), videoFormat.height.isMultiple(of: 2) else {
                        throw Self.cameraError("Camera capture format is invalid")
                    }

                    self.videoFormat = videoFormat
                    self.frameRate = frameRate
                    orientation = videoFormat.height >= videoFormat.width ? .portrait : .landscapeRight
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

                        guard output.availableVideoPixelFormatTypes.contains(
                            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                        ) else {
                            throw Self.cameraError("Camera does not support NV12 video output")
                        }
                        output.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                        ]
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(self, queue: captureQueue)
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
                        throwing: error as? XmaxError ?? Self.cameraError(error.localizedDescription)
                    )
                }
            }
        }
    }

    /// 切换摄像头，保持输出尺寸和帧率。
    ///
    /// - Parameter position: 目标摄像头位置。
    /// - Throws: 设备不可用或切换失败时抛出错误。
    func switchCamera(to position: CameraPosition) async throws {
        try Task.checkCancellation()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
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
                        throwing: error as? XmaxError ?? Self.cameraError(error.localizedDescription)
                    )
                }
            }
        }
    }

    /// 停止采集，等待正在处理的帧结束并释放设备。
    func stop() async {
        await withCheckedContinuation { continuation in
            captureQueue.async { [self] in
                stopCapture()
                continuation.resume()
            }
        }
    }

    /// 更新帧转换方向和输出尺寸，保留采集连接及帧率。
    ///
    /// - Parameters:
    ///   - orientation: 窗口显示方向。
    ///   - videoFormat: 转正后的输出尺寸和像素格式。
    /// - Throws: 采集已停止时抛出错误。
    func updateOrientation(_ orientation: CameraOrientation, videoFormat: VideoFormat) async throws {
        try Task.checkCancellation()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
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
    /// 将采集帧转换为目标尺寸和方向，并回调使用主机时钟时间戳的视频帧。
    ///
    /// - Parameters:
    ///   - output: 输出视频样本的采集输出。
    ///   - sampleBuffer: 包含像素缓冲区和采集时间戳的视频样本。
    ///   - connection: 当前视频输出的采集连接。
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let videoFormat, let frameListener,
              connection === self.output.connection(with: .video),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
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
        guard timestampUs >= 0, lastTimestampUs.map({ timestampUs > $0 }) ?? true else {
            return
        }
        lastTimestampUs = timestampUs

        do {
            let frame = try NV12VideoFrameConverter.convert(
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
            XmaxLogger.media.error(message: "摄像头帧处理失败 (Camera Frame Processing Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.localizedDescription)")
        }
    }
}

private extension CameraCaptureManager {
    /// 替换摄像头输入，并应用支持目标帧率的采集格式。
    ///
    /// - Parameter position: 目标摄像头位置。
    /// - Throws: 摄像头不可用、采集格式不受支持或设备配置失败时抛出错误。
    func replaceInput(position: CameraPosition) throws {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position == .front ? .front : .back
        ) else {
            throw Self.cameraError("The requested camera is unavailable")
        }

        // 优先选择不超过 1920×1080 的 16:9 格式，再回退到不超过 1920×1440 的 4:3 格式。
        let selected = device.formats.compactMap { format -> (
            format: AVCaptureDevice.Format, area: Int64, isWide: Bool
        )? in
            guard format.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= Double(frameRate) && Double(frameRate) <= $0.maxFrameRate
            }) else {
                return nil
            }

            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let longSide = Int64(max(dimensions.width, dimensions.height))
            let shortSide = Int64(min(dimensions.width, dimensions.height))
            let isWide = longSide * 9 == shortSide * 16
            guard longSide > 0, shortSide > 0,
                  longSide <= 1920, shortSide <= 1440,
                  isWide || longSide * 3 == shortSide * 4 else {
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
        let duration = CMTime(value: 1, timescale: Int32(frameRate))
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

    /// 设置固定的采集连接方向，并关闭系统自动镜像。
    ///
    /// - Throws: 采集连接不可用或不支持方向设置时抛出错误。
    func configureConnection() throws {
        guard let connection = output.connection(with: .video),
              connection.isVideoOrientationSupported else {
            throw Self.cameraError("Camera video orientation is unavailable")
        }

        // 固定竖向采集基准，窗口旋转由帧转换器处理。
        connection.videoOrientation = .portrait
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// 监听采集会话异常，并在媒体服务重置或中断结束后恢复采集。
    func observeSession() {
        let errorListener = errorListener
        observers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let message = error?.localizedDescription ?? "Camera capture failed"

            self?.captureQueue.async { [weak self] in
                guard let self, videoFormat != nil else {
                    return
                }

                if error?.code == AVError.mediaServicesWereReset.rawValue {
                    session.startRunning()
                    if session.isRunning { return }
                }
                errorListener?(Self.cameraError(message))
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
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
        })
    }

    /// 停止采集并移除输入、输出、观察者及帧回调。
    func stopCapture() {
        frameListener = nil
        errorListener = nil
        videoFormat = nil

        output.setSampleBufferDelegate(nil, queue: nil)
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

    /// 构造摄像头采集错误。
    ///
    /// - Parameter message: 错误描述。
    /// - Returns: 包含指定描述的媒体错误。
    static func cameraError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
