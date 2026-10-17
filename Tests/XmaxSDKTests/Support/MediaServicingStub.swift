//
//  MediaServicingStub.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import Foundation
@testable import XmaxSDK

final class MediaServicingStub: MediaServicing, @unchecked Sendable {

    // 测试配置
    let model: RealtimeModel
    private let resolvedSize: CGSize
    private let resolutionError: (any Error)?
    private let frameInterpolationSupported: Bool

    // 并发状态
    private let lock = NSLock()
    private var storedRequestedSizes: [CGSize] = []

    init(
        resolvedSize: CGSize,
        model: RealtimeModel = .x2_1_1_preview_cn,
        resolutionError: (any Error)? = nil,
        frameInterpolationSupported: Bool = false
    ) {
        self.resolvedSize = resolvedSize
        self.model = model
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

    func resolveFrameInterpolationSize(_ size: CGSize) throws -> CGSize {
        try MediaService(model: model).resolveFrameInterpolationSize(size)
    }

    func supportsFrameInterpolation(for size: CGSize) -> Bool {
        frameInterpolationSupported
    }
}
