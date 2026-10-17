//
//  MediaSourceControllingStub.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import UIKit
@testable import XmaxSDK

enum MediaSourceControllingCall: Equatable {
    case prepare(URL)
    case start
    case setLocalAudioPreviewMuted(Bool)
    case setLocalAudioVolume(Float)
    case stop
}

final class MediaSourceControllingStub:
    MediaSourceControlling,
    @unchecked Sendable {

    // 测试配置
    private let configuration: MediaSourceConfiguration
    private let prepareError: (any Error)?
    private let startError: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [MediaSourceControllingCall] = []
    private var storedLocalAudioVolume: Float = 0.45

    init(
        configuration: MediaSourceConfiguration,
        prepareError: (any Error)? = nil,
        startError: (any Error)? = nil
    ) {
        self.configuration = configuration
        self.prepareError = prepareError
        self.startError = startError
    }

    var calls: [MediaSourceControllingCall] {
        lock.withLock { storedCalls }
    }

    var hasAudio: Bool {
        configuration.hasAudio
    }

    var localAudioVolume: Float {
        get async {
            lock.withLock { storedLocalAudioVolume }
        }
    }

    func prepare(
        fileURL: URL
    ) async throws -> MediaSourceConfiguration {
        try lock.withLock {
            storedCalls.append(.prepare(fileURL))
            if let prepareError {
                throw prepareError
            }
            return configuration
        }
    }

    func start() async throws {
        try lock.withLock {
            storedCalls.append(.start)
            if let startError {
                throw startError
            }
        }
    }

    func setLocalAudioPreviewMuted(_ muted: Bool) async {
        lock.withLock {
            storedCalls.append(.setLocalAudioPreviewMuted(muted))
        }
    }

    func setLocalAudioVolume(_ volume: Float) async {
        lock.withLock {
            storedLocalAudioVolume = volume
            storedCalls.append(.setLocalAudioVolume(volume))
        }
    }

    @MainActor
    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {}

    @MainActor
    func detachPreview(from view: UIView) {}

    func stop() async {
        lock.withLock {
            storedCalls.append(.stop)
        }
    }
}
