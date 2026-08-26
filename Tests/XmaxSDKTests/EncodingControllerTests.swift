import XCTest
@testable import XmaxSDK

final class EncodingControllerTests: XCTestCase {
    func testConfigureValidatesAndAppliesAdaptiveEncodingDefaults() throws {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)

        try controller.configure(
            RealtimeVideoFormat(width: 1_024, height: 768, fps: 30)
        )

        XCTAssertEqual(
            rtcManager.encodingConfigurations,
            [
                VideoEncodingConfiguration(
                    width: 1_024,
                    height: 768,
                    frameRate: 30
                )
            ]
        )
    }

    func testConfigureRejectsInvalidFormatBeforeCallingRTC() {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)

        XCTAssertThrowsError(
            try controller.configure(
                RealtimeVideoFormat(width: 1_023, height: 768, fps: 30)
            )
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Realtime video width and height must be positive " +
                        "even numbers, and fps must be greater than zero"
                )
            )
        }
        XCTAssertTrue(rtcManager.encodingConfigurations.isEmpty)
    }

    func testConfigurePreservesRTCError() {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to configure RTC encoding"
        )
        let controller = EncodingController(
            rtcManager: RtcManagingStub(encodingError: expectedError)
        )

        XCTAssertThrowsError(
            try controller.configure(
                RealtimeVideoFormat(width: 1_024, height: 768, fps: 30)
            )
        ) { error in
            XCTAssertEqual(error as? XmaxError, expectedError)
        }
    }
}
