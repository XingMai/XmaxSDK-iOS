//
//  RtcPlatform.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A handler for remote frames copied into SDK-owned pixel buffers.
typealias RtcRemoteVideoFrameListener = @Sendable (RealtimeVideoFrame) -> Void

/// An engine interface separate from connection waits, timeouts, and leases.
protocol RtcPlatform: AnyObject, Sendable {

    /// Applies the uplink encoder configuration.
    ///
    /// - Parameter configuration: The dimensions, frame rate, bitrate, and encoding preference.
    ///
    /// - Throws: An error if the engine rejects the configuration.
    func configureVideoEncoding(
        _ configuration: VideoEncodingConfiguration
    ) throws

    /// Enables external video input.
    ///
    /// - Throws: An error if video source configuration fails.
    func useExternalVideoSource() throws

    /// Updates uplink video mirroring.
    ///
    /// - Parameter position: The current camera position.
    ///
    /// - Throws: An error if encoder mirroring cannot be configured.
    func configureLocalVideoMirror(
        for position: CameraPosition
    ) throws

    /// Switches to microphone input and starts capture.
    ///
    /// - Throws: An error if source switching or capture fails.
    func startAudioCapture() throws

    /// Stops microphone capture.
    ///
    /// - Throws: An error if the engine cannot stop capture.
    func stopAudioCapture() throws

    /// Enables external PCM input.
    ///
    /// - Throws: An error if the external audio track cannot be created.
    func startExternalAudioSource() throws

    /// Stops external PCM input and releases its track.
    ///
    /// - Throws: An error if the audio track cannot be released.
    func stopExternalAudioSource() throws

    /// Pushes an external video frame.
    ///
    /// - Parameter frame: The SDK video frame.
    ///
    /// - Throws: An error if the frame format or data is invalid.
    func pushExternalVideoFrame(
        _ frame: VideoFrame
    ) throws

    /// Pushes an external audio frame.
    ///
    /// - Parameter frame: A timestamped 10 ms PCM frame.
    ///
    /// - Throws: An error if the frame format or data is invalid.
    func pushExternalAudioFrame(
        _ frame: AudioFrame
    ) throws

    /// Creates a room adapter without connecting.
    ///
    /// - Parameter roomID: The server-assigned RTC room identifier.
    ///
    /// - Returns: An unjoined room.
    ///
    /// - Throws: An error if an unreleased room already exists.
    func createRoom(
        roomID: String
    ) throws -> any RtcRoom
}
