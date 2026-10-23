//
//  RenderControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An asynchronous handler for view interaction frames.
typealias RenderInteractionListener =
    @Sendable (
        _ frame: InteractionFrame
    ) async -> Void

/// The rendering interface used by Core.
@MainActor
protocol RenderControlling: AnyObject, Sendable {

    /// Whether remote frame interpolation is active.
    var isFrameInterpolationEnabled: Bool {
        get async
    }

    /// Changes the remote source, invalidating cached frames and waits for the previous stream.
    ///
    /// - Parameter stream: The remote stream, or `nil` to clear it.
    ///
    /// - Throws: An error if frame listener removal or attachment fails.
    func setRemoteStream(
        _ stream: RemoteStream?
    ) throws

    /// Sets the final remote video frame listener.
    ///
    /// - Parameter listener: The handler on a separate serial queue, or `nil` to remove it.
    func setRemoteVideoFrameListener(
        _ listener: RealtimeVideoFrameListener?
    )

    /// Sets serialized remote audio and processed video output.
    ///
    /// - Parameter listener: The output handler, or `nil` to stop output.
    /// - Throws: An error if the current remote audio listener cannot be configured.
    func setRemoteMediaFrameListener(
        _ listener: RealtimeMediaFrameListener?
    ) throws

    /// Registers remote rendering and trajectory interactions.
    ///
    /// - Parameters:
    ///   - track: The remote video track to register.
    ///   - resolvedMediaSize: The resolved local media dimensions for interaction mapping.
    ///   - interactionListener: The asynchronous view interaction handler.
    func registerRemoteTrack(
        _ track: RealtimeVideoTrack,
        resolvedMediaSize: CGSize,
        interactionListener: @escaping RenderInteractionListener
    )

    /// Enables or disables remote frame interpolation.
    ///
    /// - Parameters:
    ///   - enabled: Whether to enable interpolation.
    ///   - videoFormat: The expected returned format, or `nil` before local media creation.
    ///
    /// - Throws: An error if explicitly enabling unsupported interpolation.
    func setFrameInterpolationEnabled(
        _ enabled: Bool,
        videoFormat: RealtimeVideoFormat?
    ) async throws

    /// Waits for the first processed remote frame ready for display.
    ///
    /// - Throws: An error if cancelled, the remote stream is reset, or the wait times out.
    func waitUntilRemoteFrameReady() async throws

    /// Unregisters remote rendering and waits for in-flight processing.
    ///
    /// - Parameter track: The track to unregister, or `nil` to clear processing without a track.
    ///
    /// - Throws: An error if RTC frame listener removal fails.
    func resetRemoteTrack(
        _ track: RealtimeVideoTrack?
    ) async throws
}
