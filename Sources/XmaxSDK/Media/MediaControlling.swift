//
//  MediaControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A handler for media video frames.
typealias MediaVideoFrameListener = @Sendable (VideoFrame) throws -> Void

/// A handler for media audio frames.
typealias MediaAudioFrameListener = @Sendable (AudioFrame) throws -> Void

/// The media layer interface used by Core.
protocol MediaControlling: Actor, InteractionControlling {

    /// The active local video track.
    var currentTrack: RealtimeVideoTrack? {
        get
    }

    /// The current local video format.
    var currentVideoFormat: RealtimeVideoFormat? {
        get
    }

    /// Whether generation uses a separate canvas while retaining the media's aspect ratio.
    var usesContainPadding: Bool {
        get
    }

    /// Whether the source includes SDK-managed audio.
    var hasAudio: Bool {
        get
    }

    /// The local video file preview volume.
    var localAudioVolume: Float {
        get async
    }

    /// Sets a one-shot camera readiness handler.
    ///
    /// - Parameter handler: The handler called after a valid frame and preview binding, or `nil` to
    ///   remove it.
    func setCameraPreviewReadyHandler(
        _ handler: CameraPreviewReadyHandler?
    )

    /// Creates a camera stream and starts local preview.
    ///
    /// - Parameters:
    ///   - videoFormat: The requested camera video format.
    ///   - position: The initial camera position.
    ///   - useMicrophone: Whether to request microphone access and capture audio while connected.
    ///
    /// - Returns: The local camera media stream.
    ///
    /// - Throws: An error if camera permission, RTC initialization, or capture startup fails; an
    ///   existing active media source also prevents creation.
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition,
        useMicrophone: Bool
    ) async throws -> RealtimeMediaStream

    /// Starts microphone capture for a configured camera source.
    ///
    /// - Throws: An error if the operation is cancelled or RTC audio capture cannot start.
    func startMicrophoneCapture() throws

    /// Stops microphone capture while retaining camera preview and configuration.
    ///
    /// - Throws: An error if RTC audio capture cannot stop.
    func stopMicrophoneCapture() throws

    /// Stops the camera stream and releases its preview and RTC resources; other input sources are
    /// unaffected.
    func stopLocalCameraStream() async

    /// Switches the active camera position.
    ///
    /// - Returns: The local stream with its updated camera position.
    ///
    /// - Throws: An error if no camera is active, an operation conflicts, or switching fails.
    func switchCamera() async throws -> RealtimeMediaStream

    /// Updates camera orientation and dimensions for the preview window.
    ///
    /// - Throws: An error if the model rejects the dimensions or capture configuration fails.
    func updateCameraOrientation() async throws

    /// Updates the camera format while retaining its track and preview bindings.
    ///
    /// - Parameter videoFormat: The output dimensions, capture frame rate, and encoding settings.
    ///
    /// - Throws: An error if the source is not a camera, an operation conflicts, or configuration
    ///   fails.
    func updateCameraFormat(
        _ videoFormat: RealtimeVideoFormat
    ) async throws

    /// Creates a local image stream from encoded data.
    ///
    /// - Parameters:
    ///   - imageData: Encoded image data, such as PNG or JPEG.
    ///
    /// - Returns: The local track continuously delivering image frames.
    ///
    /// - Throws: An error if image data, media preparation, or external video startup fails; an
    ///   existing active media source also prevents creation.
    func createLocalImageStream(
        imageData: Data
    ) async throws -> RealtimeMediaStream

    /// Creates a local stream from a decoded image.
    ///
    /// - Parameters:
    ///   - decodedImage: The orientation-corrected decoded image.
    ///
    /// - Returns: The local track continuously delivering image frames.
    ///
    /// - Throws: An error if image processing, media preparation, or external video startup fails;
    ///   an existing active media source also prevents creation.
    func createLocalImageStream(
        decodedImage: any DecodedImage
    ) async throws -> RealtimeMediaStream

    /// Creates a local stream from an image file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local image file.
    ///
    /// - Returns: The local track continuously delivering image frames.
    ///
    /// - Throws: An error if file reading, image decoding, media preparation, or external video
    ///   startup fails; an existing active media source also prevents creation.
    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream

    /// Stops the image stream and releases frame delivery, preview, and RTC resources; other input
    /// sources are unaffected.
    func stopLocalImageStream() async

    /// Creates a local stream from a video file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local video file.
    ///
    /// - Returns: The local media stream looping the video file.
    ///
    /// - Throws: An error if file reading, media preparation, or external source startup fails; an
    ///   existing active media source also prevents creation.
    func createLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream

    /// Stops video file playback and releases preview and RTC resources; other input sources are
    /// unaffected.
    func stopLocalVideoStream() async

    /// Binds an external video source for preview.
    ///
    /// - Parameter source: The video source owned by your app.
    ///
    /// - Returns: The local media stream for preview and generation.
    ///
    /// - Throws: An error if a source exists, the format is invalid, or binding fails.
    func createExternalVideoStream(
        source: any RealtimeExternalVideoSource
    ) async throws -> RealtimeMediaStream

    /// Unbinds external video and preview without releasing your app's capture resources.
    func stopExternalVideoStream() async

    /// Stops local media and releases preview and the RTC engine; does nothing if no source is
    /// active.
    func stopLocalStream() async

    /// Mutes or restores local preview without changing playback timing or RTC audio.
    ///
    /// - Parameter muted: `true` to mute only local playback; `false` restores its configured
    ///   volume.
    func setLocalAudioPreviewMuted(
        _ muted: Bool
    ) async

    /// Sets the local video file preview volume.
    ///
    /// - Parameter volume: The validated volume, in the range `0...1`.
    func setLocalAudioVolume(
        _ volume: Float
    ) async

    /// Checks whether a stream belongs to the active media source.
    ///
    /// - Parameter stream: The stream whose ownership is checked.
    ///
    /// - Returns: `true` if the active source owns the stream's video track; otherwise `false`.
    func owns(
        _ stream: RealtimeMediaStream
    ) -> Bool
}
