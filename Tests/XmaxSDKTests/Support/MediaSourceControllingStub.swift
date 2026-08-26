import Foundation
@testable import XmaxSDK

enum MediaSourceControllingCall: Equatable {
    case prepare(URL, RealtimeVideoFormat?)
    case start
    case restart(Int64)
    case stop
}

final class MediaSourceControllingStub:
    MediaSourceControlling,
    @unchecked Sendable {

    // 测试配置
    private let configuration: MediaSourceConfiguration
    private let prepareError: (any Error)?
    private let startError: (any Error)?
    private let restartError: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [MediaSourceControllingCall] = []

    init(
        configuration: MediaSourceConfiguration,
        prepareError: (any Error)? = nil,
        startError: (any Error)? = nil,
        restartError: (any Error)? = nil
    ) {
        self.configuration = configuration
        self.prepareError = prepareError
        self.startError = startError
        self.restartError = restartError
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

    func restart(from mediaTimeUs: Int64) async throws {
        try lock.withLock {
            storedCalls.append(.restart(mediaTimeUs))
            if let restartError {
                throw restartError
            }
        }
    }

    func stop() async {
        lock.withLock {
            storedCalls.append(.stop)
        }
    }
}
