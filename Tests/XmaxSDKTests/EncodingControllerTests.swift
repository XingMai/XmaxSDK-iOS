import XCTest
@testable import XmaxSDK

final class EncodingControllerTests: XCTestCase {
    func testConfigureValidatesAndAppliesAdaptiveEncodingDefaults() throws {
        let rtcProvider = RtcProvidingStub()
        let controller = EncodingController(rtcProvider: rtcProvider)

        try controller.configure(
            RealtimeVideoFormat(width: 1_024, height: 768, fps: 30)
        )

        XCTAssertEqual(
            rtcProvider.encodingConfigurations,
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
        let rtcProvider = RtcProvidingStub()
        let controller = EncodingController(rtcProvider: rtcProvider)

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
        XCTAssertTrue(rtcProvider.encodingConfigurations.isEmpty)
    }

    func testConfigurePreservesRTCError() {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to configure RTC encoding"
        )
        let controller = EncodingController(
            rtcProvider: RtcProvidingStub(encodingError: expectedError)
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
