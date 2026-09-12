import Foundation
@testable import XmaxSDK

final class CameraCaptureManagingStub: CameraCaptureManaging, @unchecked Sendable {
    enum Call: Equatable {
        case start(VideoFormat, Int, CameraPosition)
        case switchCamera(CameraPosition)
        case stop
    }

    // 测试配置
    let startError: (any Error)?
    let switchError: (any Error)?

    // 调用记录
    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private var errorListener: XmaxErrorListener?
    private var frameListener: (@Sendable (VideoFrame) throws -> Void)?

    init(startError: (any Error)? = nil, switchError: (any Error)? = nil) {
        self.startError = startError
        self.switchError = switchError
    }

    var calls: [Call] { lock.withLock { recordedCalls } }
    var currentFrameListener: (@Sendable (VideoFrame) throws -> Void)? {
        lock.withLock { frameListener }
    }

    func start(
        videoFormat: VideoFormat,
        frameRate: Int,
        position: CameraPosition,
        frameListener: @escaping @Sendable (VideoFrame) throws -> Void,
        errorListener: @escaping XmaxErrorListener
    ) async throws {
        lock.withLock {
            recordedCalls.append(.start(videoFormat, frameRate, position))
            self.frameListener = frameListener
            self.errorListener = errorListener
        }
        if let startError { throw startError }
    }

    func switchCamera(to position: CameraPosition) async throws {
        lock.withLock { recordedCalls.append(.switchCamera(position)) }
        if let switchError { throw switchError }
    }

    func stop() async {
        lock.withLock {
            recordedCalls.append(.stop)
            frameListener = nil
            errorListener = nil
        }
    }

    var currentErrorListener: XmaxErrorListener? {
        lock.withLock { errorListener }
    }

    func emitError(_ error: XmaxError) {
        currentErrorListener?(error)
    }

    func emitFrame(_ frame: VideoFrame) throws {
        try currentFrameListener?(frame)
    }
}
