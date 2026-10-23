//
//  VideoControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for video file streams, audio preview, and playback resources.
protocol VideoControlling: Sendable {

    /// The video file track, or `nil` before creation or after stopping.
    var currentTrack: RealtimeVideoTrack? {
        get
    }

    /// Whether the video file contains SDK-managed audio.
    var hasAudio: Bool {
        get
    }

    /// The local video file preview volume.
    var localAudioVolume: Float {
        get async
    }

    /// Creates a looping local video stream.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local video file.
    ///
    /// - Returns: The local video file media stream.
    ///
    /// - Throws: An error if a stream exists, the file or format is invalid, or playback cannot
    ///   start.
    func createLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream

    /// Mutes or restores file audio preview without affecting uplink audio.
    ///
    /// - Parameter muted: `true` to mute; `false` to restore the configured preview volume.
    func setLocalAudioPreviewMuted(
        _ muted: Bool
    ) async

    /// Sets the local video file preview volume.
    ///
    /// - Parameter volume: The validated volume, from 0 to 1.
    func setLocalAudioVolume(
        _ volume: Float
    ) async

    /// Stops file playback and releases external audio and preview resources.
    func stopLocalVideoStream() async
}
