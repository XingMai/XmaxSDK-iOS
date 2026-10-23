//
//  CameraControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A preview readiness handler providing a check for stale notifications.
typealias CameraPreviewReadyHandler =
    @MainActor @Sendable (
        _ isCurrent: @escaping @Sendable () -> Bool
    ) -> Void

/// An interface for camera streams, microphone capture, and preview resources.
protocol CameraControlling: Sendable {

    /// The current camera track, or `nil` before creation or after stopping.
    var currentTrack: RealtimeVideoTrack? {
        get
    }

    /// Whether the camera stream uses microphone input.
    var useMicrophone: Bool {
        get
    }

    /// Sets a one-shot readiness handler requiring a valid frame and an attached preview.
    ///
    /// - Parameter handler: The readiness handler, or `nil` to remove it.
    func setPreviewReadyHandler(
        _ handler: CameraPreviewReadyHandler?
    )

    /// Creates and starts a local camera stream.
    ///
    /// - Parameters:
    ///   - videoFormat: The requested dimensions, frame rate, and encoding settings, subject to
    ///     model rules.
    ///   - position: The initial camera position.
    ///   - useMicrophone: Whether to request microphone access and capture audio while connected.
    ///
    /// - Returns: The local camera media stream.
    ///
    /// - Throws: An error if a camera stream exists, the format is invalid, permission is denied,
    ///   or capture fails.
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition,
        useMicrophone: Bool
    ) async throws -> RealtimeMediaStream

    /// Starts configured microphone capture without local audio playback.
    ///
    /// - Throws: An error if RTC audio configuration or microphone capture fails.
    func startMicrophoneCapture() throws

    /// Stops microphone capture while retaining its configuration.
    ///
    /// - Throws: An error if RTC microphone capture cannot stop.
    func stopMicrophoneCapture() throws

    /// Stops camera and microphone capture and releases preview resources.
    func stopLocalCameraStream() async

    /// Switches cameras while retaining the video track.
    ///
    /// - Returns: The media stream with the updated camera track.
    ///
    /// - Throws: An error if capture is inactive or camera switching or mirroring fails.
    func switchCamera() async throws -> RealtimeMediaStream

    /// Updates capture orientation and track dimensions for the window.
    ///
    /// - Parameter orientation: The requested window orientation.
    ///
    /// - Throws: An error if the model rejects the dimensions or capture configuration fails.
    func updateOrientation(
        _ orientation: CameraOrientation
    ) async throws

    /// Updates dimensions and capture frame rate while retaining the camera and preview track.
    ///
    /// - Parameter videoFormat: The new media dimensions, frame rate, and encoding settings.
    ///
    /// - Throws: An error if capture is inactive, the format is unsupported, or configuration
    ///   fails.
    func updateVideoFormat(
        _ videoFormat: RealtimeVideoFormat
    ) async throws
}
