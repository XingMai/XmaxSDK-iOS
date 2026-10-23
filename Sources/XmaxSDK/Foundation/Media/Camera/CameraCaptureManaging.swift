//
//  CameraCaptureManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// The camera frame's orientation in its window.
enum CameraOrientation: Sendable {

    /// Portrait with the device's top edge up.
    case portrait

    /// Upside-down portrait.
    case portraitUpsideDown

    /// The interface's left landscape orientation.
    case landscapeLeft

    /// The interface's right landscape orientation.
    case landscapeRight

    /// Whether the orientation is landscape.
    var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }

    /// The rotation from portrait, unmirrored capture to the window orientation.
    var frameRotation: VideoRotation {
        switch self {
        case .portrait:
            .rotation0
        case .portraitUpsideDown:
            .rotation180
        case .landscapeLeft:
            .rotation270
        case .landscapeRight:
            .rotation90
        }
    }
}

/// An interface for camera capture and raw video frames.
protocol CameraCaptureManaging: Sendable {

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
    ) async throws

    /// Switches cameras while retaining output dimensions and frame rate.
    ///
    /// - Parameter position: The requested camera position.
    ///
    /// - Throws: An error if the camera is unavailable or switching fails.
    func switchCamera(
        to position: CameraPosition
    ) async throws

    /// Updates output dimensions and capture frame rate while retaining the camera and listeners.
    ///
    /// - Parameters:
    ///   - videoFormat: The new NV12 output format.
    ///   - frameRate: The capture frame rate to apply.
    ///
    /// - Throws: An error if capture is inactive, the format is unsupported, or configuration
    ///   fails.
    func updateFormat(
        _ videoFormat: VideoFormat,
        frameRate: Int
    ) async throws

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
    ) async throws

    /// Stops capture and waits for pending frames before releasing the device.
    func stop() async
}
