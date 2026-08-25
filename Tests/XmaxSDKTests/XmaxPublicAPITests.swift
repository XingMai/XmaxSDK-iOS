import CoreGraphics
import Foundation
import UIKit
import XCTest
import XmaxSDK

final class XmaxPublicAPITests: XCTestCase {
    @MainActor
    func testClientCreatesPublicRealtimeManager() {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: "test-key")
        )

        let manager: any XmaxRealtimeManaging = client.createRealtimeManager(
            options: RealtimeConfiguration(model: .x2_0)
        )

        XCTAssertEqual(manager.options.model, .x2_0)
    }

    func testPublicRealtimeCameraModelsAreConstructible() throws {
        let format = RealtimeVideoFormat(
            width: 1_024,
            height: 768,
            fps: 30
        )
        let position: CameraPosition = .front

        try format.validate()

        XCTAssertEqual(format.width, 1_024)
        XCTAssertEqual(format.height, 768)
        XCTAssertEqual(format.fps, 30)
        XCTAssertEqual(position.rawValue, "front")
    }

    @MainActor
    func testPublicVideoViewAcceptsRealtimeTrackAndContentMode() {
        let view = XmaxVideoView(videoContentMode: .fit)

        view.track = nil
        view.videoContentMode = .fill

        XCTAssertNil(view.track)
        XCTAssertEqual(view.videoContentMode, .fill)
    }

    @MainActor
    func testClientCreatesPublicMediaService() {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: "test-key")
        )

        let service: any MediaServicing = client.createMediaService()

        XCTAssertNotNil(service as Any)
    }

    private func readPublicProcessedImage(
        _ image: ProcessedImage
    ) -> (Data, CGSize, String) {
        (image.data, image.size, image.contentType)
    }

    private func presentPicker(
        using service: any MediaServicing,
        from viewController: UIViewController
    ) async throws -> Data {
        try await service.pickImage(from: viewController)
    }

    private func createDefaultCameraStream(
        using manager: any XmaxRealtimeManaging,
        videoFormat: RealtimeVideoFormat
    ) async throws -> RealtimeMediaStream {
        try await manager.createLocalCameraStream(videoFormat: videoFormat)
    }

    private func stopCameraStream(
        using manager: any XmaxRealtimeManaging
    ) async throws {
        try await manager.stopLocalCameraStream()
    }

    private func readPublicRealtimeStream(
        _ stream: RealtimeMediaStream
    ) -> (String, String?, RealtimeVideoFormat?, CameraPosition?) {
        (
            stream.id,
            stream.videoTrack?.id,
            stream.videoTrack?.videoFormat,
            stream.videoTrack?.position
        )
    }
}
