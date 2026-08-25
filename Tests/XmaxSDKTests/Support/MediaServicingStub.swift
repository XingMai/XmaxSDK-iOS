import CoreGraphics
import Foundation
import UIKit
@testable import XmaxSDK

final class MediaServicingStub: MediaServicing, @unchecked Sendable {

    // 测试配置
    private let resolvedSize: CGSize
    private let resolutionError: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedRequestedSizes: [CGSize] = []

    init(
        resolvedSize: CGSize,
        resolutionError: (any Error)? = nil
    ) {
        self.resolvedSize = resolvedSize
        self.resolutionError = resolutionError
    }

    var requestedSizes: [CGSize] {
        lock.withLock { storedRequestedSizes }
    }

    @MainActor
    func pickImage(
        from presentingViewController: UIViewController
    ) async throws -> Data {
        Data()
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

    func resizeToModelInput(
        _ data: Data
    ) async throws -> ProcessedImage {
        ProcessedImage(
            data: data,
            size: resolvedSize,
            contentType: "image/jpeg"
        )
    }

    func resizeToFit(
        _ data: Data,
        maximumSize: CGSize
    ) async throws -> ProcessedImage {
        ProcessedImage(
            data: data,
            size: maximumSize,
            contentType: "image/jpeg"
        )
    }

    func compressJPEG(
        _ data: Data,
        quality: Double
    ) async throws -> ProcessedImage {
        ProcessedImage(
            data: data,
            size: resolvedSize,
            contentType: "image/jpeg"
        )
    }
}
