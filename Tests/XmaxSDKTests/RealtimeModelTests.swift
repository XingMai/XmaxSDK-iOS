import XCTest
@testable import XmaxSDK

final class RealtimeModelTests: XCTestCase {
    func testContextNormalizesPromptAndReferencePath() {
        XCTAssertEqual(
            RealtimeContext(
                prompt: "  animate this  ",
                referencePath: "  /image.png  "
            ),
            RealtimeContext(
                prompt: "animate this",
                referencePath: "/image.png"
            )
        )
        XCTAssertNil(
            RealtimeContext(prompt: "prompt", referencePath: " \n ")
                .referencePath
        )
    }

    func testVideoFormatRequiresPositiveEvenDimensions() throws {
        XCTAssertNoThrow(
            try RealtimeVideoFormat(width: 720, height: 1280, fps: 30)
                .validate()
        )

        XCTAssertThrowsError(
            try RealtimeVideoFormat(width: 721, height: 1280, fps: 30)
                .validate()
        ) { error in
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }
        XCTAssertThrowsError(
            try RealtimeVideoFormat(width: 720, height: 1280, fps: 0)
                .validate()
        ) { error in
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }
    }

    func testVideoTrackUpdatesReadableMetadata() {
        let emptyTrack = RealtimeVideoTrack(id: "empty-track")
        let track = RealtimeVideoTrack(
            id: "track-1",
            videoFormat: RealtimeVideoFormat(
                width: 720,
                height: 1280,
                fps: 30
            ),
            position: .front
        )

        track.updateVideoFormat(
            RealtimeVideoFormat(
                width: 1080,
                height: 1920,
                fps: 24
            )
        )
        track.updatePosition(.back)

        XCTAssertEqual(track.id, "track-1")
        XCTAssertEqual(
            track.videoFormat,
            RealtimeVideoFormat(width: 1080, height: 1920, fps: 24)
        )
        XCTAssertEqual(track.position, .back)
        XCTAssertNil(emptyTrack.videoFormat)
        XCTAssertNil(emptyTrack.position)
    }

    func testRealtimeEnumRawValuesMatchCrossPlatformContract() {
        XCTAssertEqual(RealtimeConnectionState.generating.rawValue, "Generating")
        XCTAssertEqual(RealtimeNetworkQualityLevel.veryBad.rawValue, "VeryBad")
        XCTAssertEqual(RealtimePerformanceStatus.recovered.rawValue, "Recovered")
    }
}
