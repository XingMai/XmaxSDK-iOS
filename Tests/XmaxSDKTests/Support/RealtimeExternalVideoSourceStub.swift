//
//  RealtimeExternalVideoSourceStub.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@testable import XmaxSDK

@MainActor
final class RealtimeExternalVideoSourceStub: RealtimeExternalVideoSource {
    let videoFormat: RealtimeVideoFormat
    let hasAudio: Bool
    var sink: (any RealtimeExternalFrameSink)?
    var stopCount = 0
    var startHandler: (@MainActor () async throws -> Void)?

    init(videoFormat: RealtimeVideoFormat = RealtimeVideoFormat(width: 1280, height: 720, fps: 24), hasAudio: Bool = false) {
        self.videoFormat = videoFormat
        self.hasAudio = hasAudio
    }

    func start(sink: any RealtimeExternalFrameSink) async throws {
        self.sink = sink
        try await startHandler?()
    }

    func stop() async {
        stopCount += 1
        sink = nil
    }
}
