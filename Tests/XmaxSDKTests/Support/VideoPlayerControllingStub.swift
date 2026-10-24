//
//  VideoPlayerControllingStub.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit
@testable import XmaxSDK

enum VideoPlayerControllingCall: Equatable {
    case configure(
        fileURL: URL,
        metadata: MediaFileMetadata,
        videoFormat: RealtimeVideoFormat
    )
    case start
    case setLocalAudioPreviewMuted(Bool)
    case setLocalAudioVolume(Float)
    case attachPreview
    case detachPreview
    case stop
}

@MainActor
final class VideoPlayerControllingStub: VideoPlayerControlling {
    private(set) var calls: [VideoPlayerControllingCall] = []
    private(set) var localAudioVolume: Float = 0.45
    var configureError: (any Error)?
    var startError: (any Error)?
    var startHandler: (@MainActor () async throws -> Void)?

    func configure(
        fileURL: URL,
        metadata: MediaFileMetadata,
        videoFormat: RealtimeVideoFormat
    ) throws {
        calls.append(.configure(
            fileURL: fileURL,
            metadata: metadata,
            videoFormat: videoFormat
        ))
        if let configureError { throw configureError }
    }

    func start() async throws {
        calls.append(.start)
        if let startError { throw startError }
        try await startHandler?()
    }

    func setLocalAudioPreviewMuted(_ muted: Bool) {
        calls.append(.setLocalAudioPreviewMuted(muted))
    }

    func setLocalAudioVolume(_ volume: Float) {
        localAudioVolume = volume
        calls.append(.setLocalAudioVolume(volume))
    }

    func attachPreview(to view: UIView, contentMode: VideoContentMode) throws {
        calls.append(.attachPreview)
    }

    func detachPreview(from view: UIView) {
        calls.append(.detachPreview)
    }

    func stop() async {
        calls.append(.stop)
    }
}
