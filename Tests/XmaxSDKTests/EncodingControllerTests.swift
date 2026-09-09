import XCTest
@testable import XmaxSDK

final class EncodingControllerTests: XCTestCase {
    func testConfigureScalesBitrateByUploadAreaAndFrameRate() throws {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)
        let cases = [
            (width: 1920, height: 1080, fps: 30, minimum: 3150, maximum: 6300),
            (width: 832, height: 1472, fps: 24, minimum: 1488, maximum: 2977),
            (width: 1472, height: 832, fps: 24, minimum: 1488, maximum: 2977),
            (width: 1024, height: 1920, fps: 30, minimum: 2987, maximum: 5973),
            (width: 1024, height: 768, fps: 30, minimum: 1195, maximum: 2389),
            (width: 1024, height: 768, fps: 24, minimum: 956, maximum: 1911),
            (width: 2, height: 2, fps: 1, minimum: 1, maximum: 2)
        ]

        for testCase in cases {
            try controller.configure(
                RealtimeVideoFormat(width: testCase.width, height: testCase.height, fps: testCase.fps)
            )

            XCTAssertEqual(
                rtcManager.encodingConfigurations.last,
                VideoEncodingConfiguration(
                    width: testCase.width,
                    height: testCase.height,
                    frameRate: testCase.fps,
                    minimumBitrate: testCase.minimum,
                    maximumBitrate: testCase.maximum
                )
            )
        }
    }

    func testConfigureRejectsBitrateOverflowBeforeCallingRTC() {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)

        XCTAssertThrowsError(
            try controller.configure(
                RealtimeVideoFormat(width: Int.max - 1, height: Int.max - 1, fps: Int.max)
            )
        ) { error in
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }
        XCTAssertTrue(rtcManager.encodingConfigurations.isEmpty)
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
