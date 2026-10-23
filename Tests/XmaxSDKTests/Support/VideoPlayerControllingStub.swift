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
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool,
        durationSeconds: Double
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
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool,
        durationSeconds: Double
    ) throws {
        calls.append(.configure(
            fileURL: fileURL,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            rotation: rotation,
            frameRate: frameRate,
            hasAudio: hasAudio,
            durationSeconds: durationSeconds
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
