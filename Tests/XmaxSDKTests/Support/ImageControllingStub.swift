import CoreGraphics
import Foundation
@testable import XmaxSDK

enum ImageControllingCall: Equatable {
    case createData(Data, RealtimeVideoFormat?)
    case createDecoded(CGSize, RealtimeVideoFormat?)
    case createFile(URL, RealtimeVideoFormat?)
    case stop
}

final class ImageControllingStub: ImageControlling, @unchecked Sendable {

    // 测试配置
    private let resolvedFormat: RealtimeVideoFormat

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [ImageControllingCall] = []
    private var activeTrack: RealtimeVideoTrack?

    init(resolvedFormat: RealtimeVideoFormat) {
        self.resolvedFormat = resolvedFormat
    }

    var calls: [ImageControllingCall] {
        lock.withLock { storedCalls }
    }

    var currentTrack: RealtimeVideoTrack? {
        lock.withLock { activeTrack }
    }

    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        createStream(call: .createData(imageData, videoFormat))
    }

    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        createStream(call: .createDecoded(decodedImage.size, videoFormat))
    }

    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        createStream(call: .createFile(fileURL, videoFormat))
    }

    func stopLocalImageStream() async {
        lock.withLock {
            storedCalls.append(.stop)
            activeTrack = nil
        }
    }

    private func createStream(call: ImageControllingCall) -> RealtimeMediaStream {
        lock.withLock {
            storedCalls.append(call)
            let track = RealtimeVideoTrack(id: "video0", videoFormat: resolvedFormat)
            activeTrack = track
            return RealtimeMediaStream(id: StreamID.local.rawValue, videoTrack: track)
        }
    }
}
