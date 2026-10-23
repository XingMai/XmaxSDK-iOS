//
//  XmaxRealtimeManaging+Extension.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Convenience methods for media creation and realtime generation.
public extension XmaxRealtimeManaging {

    /// Creates a camera stream using a preset and the model's recommended frame rate.
    ///
    /// - Parameters:
    ///   - preset: The camera resolution, which must be supported by the model.
    ///   - position: The camera position to use initially.
    ///   - useMicrophone: Whether to capture microphone audio while connected.
    ///
    /// - Returns: A media stream containing the local camera track.
    ///
    /// - Throws: An error if the preset is unsupported, permission is denied, an operation
    ///   conflicts, or capture cannot start.
    func createLocalCameraStream(
        preset: RealtimeCameraPreset,
        position: CameraPosition = .front,
        useMicrophone: Bool = false
    ) async throws -> RealtimeMediaStream {
        guard
            let format = options.model.supportedVideoFormats.first(
                where: {
                    $0.size == preset.size
                }
            )
        else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Model does not support the requested camera preset"
            )
        }
        return try await createLocalCameraStream(
            videoFormat: format,
            position: position,
            useMicrophone: useMicrophone
        )
    }

    /// Creates a camera stream using the model's default video format.
    ///
    /// - Parameters:
    ///   - position: The camera position. The default is the front camera.
    ///   - useMicrophone: Whether to capture microphone audio while connected. The default is
    ///     `false`.
    ///
    /// - Returns: A media stream containing the local camera video track.
    ///
    /// - Throws: An error if configuration is invalid, a required permission is denied, an
    ///   operation conflicts, or capture cannot start.
    func createLocalCameraStream(
        position: CameraPosition = .front,
        useMicrophone: Bool = false
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: options.model.defaultCameraVideoFormat,
            position: position,
            useMicrophone: useMicrophone
        )
    }

    /// Creates a front camera stream and starts its preview.
    ///
    /// - Parameters:
    ///   - videoFormat: The camera capture and encoding format.
    ///   - useMicrophone: Whether to capture microphone audio while connected. The default is
    ///     `false`.
    ///
    /// - Returns: A media stream containing the local camera video track.
    ///
    /// - Throws: An error if configuration is invalid, a required permission is denied, an
    ///   operation conflicts, or capture cannot start.
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        useMicrophone: Bool = false
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front,
            useMicrophone: useMicrophone
        )
    }

    /// Creates a local camera stream without microphone input.
    ///
    /// - Parameters:
    ///   - videoFormat: The camera capture and encoding format.
    ///   - position: The camera position to use initially.
    ///
    /// - Returns: A media stream containing the local camera video track.
    ///
    /// - Throws: An error if configuration is invalid, a required permission is denied, an
    ///   operation conflicts, or capture cannot start.
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: videoFormat,
            position: position,
            useMicrophone: false
        )
    }

    /// Starts or updates generation using cached conditions.
    ///
    /// For the first request, use an overload that accepts a context.
    ///
    /// - Parameter faceRestoration: Whether to restore the original face. The default is `false`.
    ///
    /// - Throws: An error if no cached conditions exist or generation startup or an update fails.
    func startGeneration(
        faceRestoration: Bool = false
    ) async throws {
        try await startGeneration(
            context: nil,
            faceRestoration: faceRestoration
        )
    }

    /// Starts or updates generation without face restoration.
    ///
    /// - Parameter context: The requested conditions, or `nil` to reuse cached conditions.
    ///
    /// - Throws: An error if conditions are invalid or generation startup or an update fails.
    func startGeneration(
        context: RealtimeContext?
    ) async throws {
        try await startGeneration(
            context: context,
            faceRestoration: false
        )
    }

    /// Connects a local stream if needed and starts generation without face restoration.
    ///
    /// - Parameters:
    ///   - localStream: The active local media stream owned by this manager.
    ///   - context: The generation conditions. Required for the first request.
    ///
    /// - Returns: The remote stream for the current connection.
    ///
    /// - Throws: An error if the local stream is invalid or connection or generation startup fails.
    func startGeneration(
        localStream: RealtimeMediaStream,
        context: RealtimeContext?
    ) async throws -> RealtimeMediaStream {
        try await startGeneration(
            localStream: localStream,
            context: context,
            faceRestoration: false
        )
    }

    /// Connects a local stream if needed and starts generation using cached conditions.
    ///
    /// For the first request, use an overload that accepts a context.
    ///
    /// - Parameters:
    ///   - localStream: The active local media stream owned by this manager.
    ///   - faceRestoration: Whether to restore the original face. The default is `false`.
    ///
    /// - Returns: The remote media stream for the current RTC connection.
    ///
    /// - Throws: An error if no cached conditions exist, the stream is invalid, or connection or
    ///   generation startup fails.
    func startGeneration(
        localStream: RealtimeMediaStream,
        faceRestoration: Bool = false
    ) async throws -> RealtimeMediaStream {
        try await startGeneration(
            localStream: localStream,
            context: nil,
            faceRestoration: faceRestoration
        )
    }
}
