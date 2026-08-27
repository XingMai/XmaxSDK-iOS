import CoreGraphics
import Foundation
@testable import XmaxSDK

final class MediaServicingStub: MediaServicing, @unchecked Sendable {

    // 测试配置
    private let resolvedSize: CGSize
    private let resolutionError: (any Error)?
    private let frameInterpolationSupported: Bool

    // 并发状态
    private let lock = NSLock()
    private var storedRequestedSizes: [CGSize] = []

    init(
        resolvedSize: CGSize,
        resolutionError: (any Error)? = nil,
        frameInterpolationSupported: Bool = false
    ) {
        self.resolvedSize = resolvedSize
        self.resolutionError = resolutionError
        self.frameInterpolationSupported = frameInterpolationSupported
    }

    var requestedSizes: [CGSize] {
        lock.withLock { storedRequestedSizes }
    }

    func resolveModelInputSize(_ size: CGSize) throws -> CGSize {
        try lock.withLock {
            storedRequestedSizes.append(size)
            if let resolutionError {
                throw resolutionError
            }
            return resolvedSize
        }
    }

    func supportsFrameInterpolation(for size: CGSize) -> Bool {
        frameInterpolationSupported
    }
}
