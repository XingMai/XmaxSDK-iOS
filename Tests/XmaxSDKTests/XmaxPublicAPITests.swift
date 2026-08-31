import CoreGraphics
import CoreMedia
import Foundation
import UIKit
import XCTest
import XmaxSDK

final class XmaxPublicAPITests: XCTestCase {
    func testPublicLoggerOptionsAreComposable() {
        let options: XmaxLoggerOption = [.business, .performance]
        let configuration = XmaxConfiguration(
            apiKey: "test-key",
            loggerOptions: options
        )

        XCTAssertEqual(options, .all)
        XCTAssertEqual(configuration.loggerOptions, .all)
    }

    @MainActor
    func testClientCreatesPublicRealtimeManager() {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: "test-key")
        )

        let manager: any XmaxRealtimeManaging = client.createRealtimeManager(
            options: RealtimeConfiguration(
                model: .x2_0,
                isFrameInterpolationEnabled: true
            )
        )

        XCTAssertEqual(manager.options.model, .x2_0)
        XCTAssertTrue(manager.options.isFrameInterpolationEnabled)
    }

    @MainActor
    func testPublicRemoteVideoFrameListenerIsAvailable() async {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: "test-key")
        )
        let manager = client.createRealtimeManager(
            options: RealtimeConfiguration(model: .x2_0)
        )
        let listener: RealtimeVideoFrameListener = { frame in
            _ = frame.pixelBuffer
            _ = frame.presentationTimeStamp
            _ = frame.duration
        }

        await manager.setRemoteVideoFrameListener(listener)
        await manager.setRemoteVideoFrameListener(nil)

        XCTAssertNotNil(listener)
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

    func testPublicRealtimeContextIsConstructible() {
        let context = RealtimeContext(
            prompt: " prompt ",
            referencePath: " reference/image.png "
        )

        XCTAssertEqual(context.prompt, "prompt")
        XCTAssertEqual(context.referencePath, "reference/image.png")
    }

    @MainActor
    func testPublicRealtimeQualityModelsAreConstructible() {
        let networkQuality = RealtimeNetworkQuality(
            uplink: .excellent,
            downlink: .good
        )
        let performanceAlarm = RealtimePerformanceAlarm(
            status: .limited,
            suggestedVideoFormat: RealtimeVideoFormat(
                width: 540,
                height: 960,
                fps: 15
            )
        )
        let networkListener: RealtimeNetworkQualityListener = { _ in }
        let performanceListener: RealtimePerformanceAlarmListener = { _ in }

        networkListener(networkQuality)
        performanceListener(performanceAlarm)

        XCTAssertEqual(networkQuality.uplink, .excellent)
        XCTAssertEqual(networkQuality.downlink, .good)
        XCTAssertEqual(performanceAlarm.status, .limited)
        XCTAssertEqual(performanceAlarm.suggestedVideoFormat?.fps, 15)
    }

    @MainActor
    func testPublicVideoViewAcceptsRealtimeTrackAndContentMode() {
        let view = XmaxVideoView(
            videoContentMode: .fit,
            isInteractionEnabled: false
        )

        view.track = nil
        view.videoContentMode = .fill

        XCTAssertNil(view.track)
        XCTAssertEqual(view.videoContentMode, .fill)
        XCTAssertFalse(view.isInteractionEnabled)
    }

    @MainActor
    func testPublicSwiftUIVideoAcceptsTrackAndDisplayOptions() {
        let video = XmaxVideo(
            track: nil,
            videoContentMode: .fit,
            isInteractionEnabled: false
        )

        XCTAssertNil(video.track)
        XCTAssertEqual(video.videoContentMode, .fit)
        XCTAssertFalse(video.isInteractionEnabled)
    }

    @MainActor
    func testClientCreatesPublicMediaService() {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: "test-key")
        )

        let service: any MediaServicing = client.createMediaService()

        XCTAssertNotNil(service as Any)
        XCTAssertFalse(
            service.supportsFrameInterpolation(
                for: CGSize(width: 0, height: 1_280)
            )
        )
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

    private func createDefaultImageStream(
        using manager: any XmaxRealtimeManaging,
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await manager.createLocalImageStream(fileURL: fileURL)
    }

    private func createImageDataStream(
        using manager: any XmaxRealtimeManaging,
        imageData: Data
    ) async throws -> RealtimeMediaStream {
        try await manager.createLocalImageStream(imageData: imageData)
    }

    @MainActor
    private func createUIKitImageStream(
        using manager: any XmaxRealtimeManaging,
        image: UIImage
    ) async throws -> RealtimeMediaStream {
        try await manager.createLocalImageStream(image: image)
    }

    private func stopImageStream(
        using manager: any XmaxRealtimeManaging
    ) async throws {
        try await manager.stopLocalImageStream()
    }

    private func createDefaultVideoStream(
        using manager: any XmaxRealtimeManaging,
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await manager.createLocalVideoStream(fileURL: fileURL)
    }

    private func stopVideoStream(
        using manager: any XmaxRealtimeManaging
    ) async throws {
        try await manager.stopLocalVideoStream()
    }

    private func startGeneration(
        using manager: any XmaxRealtimeManaging,
        localStream: RealtimeMediaStream,
        context: RealtimeContext?
    ) async throws -> RealtimeMediaStream {
        try await manager.startGeneration(
            localStream: localStream,
            context: context
        )
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
