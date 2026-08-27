import Foundation
import UIKit
@testable import XmaxSDK

enum MediaSourceControllingCall: Equatable {
    case prepare(URL, RealtimeVideoFormat?)
    case start
    case setLocalAudioPreviewEnabled(Bool)
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

    func prepare(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> MediaSourceConfiguration {
        try lock.withLock {
            storedCalls.append(.prepare(fileURL, videoFormat))
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

    func setLocalAudioPreviewEnabled(_ enabled: Bool) async throws {
        lock.withLock {
            storedCalls.append(.setLocalAudioPreviewEnabled(enabled))
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
