import Foundation
@testable import XmaxSDK

/// Controls result-frame readiness independently of transport publication in generation tests.
@MainActor
final class RenderControllingStub: RenderControlling {
    var isFrameInterpolationEnabled = false
    var frameReadyHandler: (@MainActor @Sendable () async throws -> Void)?
    private(set) var frameReadyWaitCount = 0

    func setRemoteStream(_ stream: RemoteStream?) throws {}
    func setRemoteVideoFrameListener(_ listener: RealtimeVideoFrameListener?) {}
    func setRemoteMediaFrameListener(_ listener: RealtimeMediaFrameListener?) throws {}
    func registerRemoteTrack(
        _ track: RealtimeVideoTrack,
        resolvedMediaSize: CGSize,
        interactionListener: @escaping RenderInteractionListener
    ) {}
    func setFrameInterpolationEnabled(
        _ enabled: Bool,
        videoFormat: RealtimeVideoFormat?
    ) async throws {
        isFrameInterpolationEnabled = enabled
    }
    func waitUntilRemoteFrameReady() async throws {
        frameReadyWaitCount += 1
        try await frameReadyHandler?()
    }
    func resetRemoteTrack(_ track: RealtimeVideoTrack?) async throws {}
}
