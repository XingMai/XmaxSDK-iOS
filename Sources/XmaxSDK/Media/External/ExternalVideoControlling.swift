//
//  ExternalVideoControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// An interface for external video binding, tracks, and preview.
protocol ExternalVideoControlling: Sendable {

    /// The external video track, or `nil` after unbinding.
    var currentTrack: RealtimeVideoTrack? {
        get
    }

    /// Whether the current source supplies external audio for publication.
    var hasAudio: Bool {
        get
    }

    /// Binds an external source without taking ownership of its capture resources.
    ///
    /// - Parameter source: The external source owned by your app.
    ///
    /// - Returns: The local stream for preview and generation.
    ///
    /// - Throws: An error if the format is invalid, a binding exists, or RTC or source startup
    ///   fails.
    @MainActor
    func createExternalVideoStream(
        source: any RealtimeExternalVideoSource
    ) async throws -> RealtimeMediaStream

    /// Stops frame delivery and preview and unbinds the source.
    @MainActor
    func stopExternalVideoStream() async
}
