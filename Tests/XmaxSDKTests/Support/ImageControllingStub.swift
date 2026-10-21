//
//  ImageControllingStub.swift
//  XmaxSDK
//  Repo: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import Foundation
@testable import XmaxSDK

enum ImageControllingCall: Equatable {
    case createData(Data)
    case createDecoded(CGSize)
    case createFile(URL)
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
        imageData: Data
    ) async throws -> RealtimeMediaStream {
        createStream(call: .createData(imageData))
    }

    func createLocalImageStream(
        decodedImage: any DecodedImage
    ) async throws -> RealtimeMediaStream {
        createStream(call: .createDecoded(decodedImage.size))
    }

    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        createStream(call: .createFile(fileURL))
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
