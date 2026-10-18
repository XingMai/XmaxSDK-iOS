//
//  MediaServicingStub.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

    func resolveMediaSize(_ size: CGSize, source: RealtimeMediaSource) throws -> CGSize {
        try lock.withLock {
            storedRequestedSizes.append(size)
            if let resolutionError {
                throw resolutionError
            }
            return source == .camera ? resolvedSize : try MediaService(model: model).resolveMediaSize(size, source: source)
        }
    }

    func resolveTargetSize(_ sourceSize: CGSize, maximumSize: CGSize, frameInterpolationEnabled: Bool) throws -> CGSize {
        try MediaService(model: model).resolveTargetSize(
            sourceSize,
            maximumSize: maximumSize,
            frameInterpolationEnabled: frameInterpolationEnabled
        )
    }

    func supportsFrameInterpolation(for size: CGSize) -> Bool {
        frameInterpolationSupported
    }
}
