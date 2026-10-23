//
//  RealtimeVideoTrack.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A realtime video track with dynamic metadata.
public final class RealtimeVideoTrack: @unchecked Sendable {

    /// The video track identifier.
    public let id: String

    /// The lock protecting mutable track metadata.
    private let metadataLock = NSLock()

    /// The synchronized media format and camera position.
    private var metadata: Metadata

    /// The camera display orientation reported by the view.
    @MainActor var displayOrientation: CameraOrientation?

    /// The orientation handler indicating whether portrait-landscape axis changed.
    @MainActor var orientationChangeHandler: ((_ changedAxis: Bool) -> Void)?

    /// Creates a video track.
    ///
    /// - Parameters:
    ///   - id: The unique track identifier.
    ///   - videoFormat: The initial video format, or `nil` if unresolved.
    ///   - position: The camera position, or `nil` for a noncamera track.
    init(
        id: String,
        videoFormat: RealtimeVideoFormat? = nil,
        position: CameraPosition? = nil
    ) {
        self.id = id
        metadata = Metadata(
            videoFormat: videoFormat,
            position: position
        )
    }

    /// The track's current video format.
    public var videoFormat: RealtimeVideoFormat? {
        metadataLock.withLock {
            metadata.videoFormat
        }
    }

    /// The local camera track's current camera position.
    public var position: CameraPosition? {
        metadataLock.withLock {
            metadata.position
        }
    }

    /// Updates the track's video format.
    ///
    /// - Parameter videoFormat: The new dimensions, frame rate, and encoding settings.
    func updateVideoFormat(
        _ videoFormat: RealtimeVideoFormat
    ) {
        metadataLock.withLock {
            metadata.videoFormat = videoFormat
        }
    }

    /// Updates the local track's camera position.
    ///
    /// - Parameter position: The active capture camera.
    func updatePosition(
        _ position: CameraPosition
    ) {
        metadataLock.withLock {
            metadata.position = position
        }
    }
}

private extension RealtimeVideoTrack {

    /// The mutable video format and camera position.
    struct Metadata {

        /// The resolved media dimensions, frame rate, and encoding settings.
        var videoFormat: RealtimeVideoFormat?

        /// The camera position, if this is a camera track.
        var position: CameraPosition?
    }
}
