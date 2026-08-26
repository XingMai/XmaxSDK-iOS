import XCTest
@testable import XmaxSDK

final class InteractionCoordinateMapperTests: XCTestCase {
    func testFitMapsDisplayedVideoAndRejectsLetterboxArea() throws {
        let viewportSize = CGSize(width: 320, height: 480)
        let videoSize = CGSize(width: 720, height: 1280)

        XCTAssertNil(
            InteractionCoordinateMapper.map(
                CGPoint(x: 10, y: 240),
                viewportSize: viewportSize,
                videoSize: videoSize,
                contentMode: .fit
            )
        )
        XCTAssertEqual(
            InteractionCoordinateMapper.map(
                CGPoint(x: 160, y: 240),
                viewportSize: viewportSize,
                videoSize: videoSize,
                contentMode: .fit
            ),
            RealtimePoint(x: 360, y: 640)
        )
    }

    func testFillIncludesCroppedVideoOffset() throws {
        XCTAssertEqual(
            InteractionCoordinateMapper.map(
                CGPoint(x: 0, y: 0),
                viewportSize: CGSize(width: 320, height: 480),
                videoSize: CGSize(width: 720, height: 1280),
                contentMode: .fill
            ),
            RealtimePoint(x: 0, y: 100)
        )
    }

    func testInvalidGeometryDoesNotProducePoint() {
        XCTAssertNil(
            InteractionCoordinateMapper.map(
                CGPoint(x: 10, y: 10),
                viewportSize: .zero,
                videoSize: CGSize(width: 720, height: 1280),
                contentMode: .fill
            )
        )
    }
}
