import CoreGraphics
import Foundation
@testable import XmaxSDK

enum ImageSourceControllingCall: Equatable {
    case prepareData(Data, RealtimeVideoFormat?)
    case prepareDecoded(CGSize, RealtimeVideoFormat?)
    case prepare(URL, RealtimeVideoFormat?)
    case start
    case stop
}

final class ImageSourceControllingStub:
    ImageSourceControlling,
    @unchecked Sendable {

    // 测试配置
    private let resolvedFormat: RealtimeVideoFormat
    private let prepareError: (any Error)?
    private let startError: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [ImageSourceControllingCall] = []

    init(
        resolvedFormat: RealtimeVideoFormat,
        prepareError: (any Error)? = nil,
        startError: (any Error)? = nil
    ) {
        self.resolvedFormat = resolvedFormat
        self.prepareError = prepareError
        self.startError = startError
    }

    var calls: [ImageSourceControllingCall] {
        lock.withLock { storedCalls }
    }

    func prepare(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeVideoFormat {
        try lock.withLock {
            storedCalls.append(.prepareData(imageData, videoFormat))
            if let prepareError {
                throw prepareError
            }
            return resolvedFormat
        }
    }

    func prepare(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeVideoFormat {
        try lock.withLock {
            storedCalls.append(
                .prepareDecoded(decodedImage.size, videoFormat)
            )
            if let prepareError {
                throw prepareError
            }
            return resolvedFormat
        }
    }

    func prepare(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeVideoFormat {
        try lock.withLock {
            storedCalls.append(.prepare(fileURL, videoFormat))
            if let prepareError {
                throw prepareError
            }
            return resolvedFormat
        }
    }

    func start() throws {
        try lock.withLock {
            storedCalls.append(.start)
            if let startError {
                throw startError
            }
        }
    }

    func stop() {
        lock.withLock {
            storedCalls.append(.stop)
        }
    }
}
