import XCTest
@testable import XmaxSDK

final class EncodingControllerTests: XCTestCase {
    func testConfigureAppliesExplicitBitratesAndEncoderPreference() throws {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)
        let cases: [(
            minimum: Int?, maximum: Int?, preference: RealtimeVideoEncoderPreference,
            expectedMinimum: Int, expectedMaximum: Int,
            expectedPreference: VideoEncodingConfiguration.EncoderPreference
        )] = [
            (1500, 3000, .auto, 1500, 3000, .auto),
            (0, 500, .maintainQuality, 0, 500, .maintainQuality),
            (nil, 4000, .maintainFramerate, 1805, 4000, .maintainFramerate),
            (1500, nil, .auto, 1500, 3611, .auto),
            (2000, 2000, .auto, 2000, 2000, .auto),
            (nil, nil, .maintainQuality, 1805, 3611, .maintainQuality)
        ]

        for testCase in cases {
            let format = RealtimeVideoFormat(
                width: 832, height: 1472, fps: 24,
                minimumBitrate: testCase.minimum,
                maximumBitrate: testCase.maximum,
                encoderPreference: testCase.preference
            )
            try controller.configure(format)
            XCTAssertEqual(
                rtcManager.encodingConfigurations.last,
                VideoEncodingConfiguration(
                    width: 832, height: 1472, frameRate: 24,
                    minimumBitrate: testCase.expectedMinimum,
                    maximumBitrate: testCase.expectedMaximum,
                    encoderPreference: testCase.expectedPreference
                )
            )
        }
    }

    func testConfigureRejectsInvalidExplicitAndMergedBitrateRangesBeforeRTC() {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)
        let cases: [(minimum: Int?, maximum: Int?)] = [
            (-1, nil), (nil, -1), (nil, 0), (3000, 1500), (4000, nil), (nil, 1000)
        ]

        for testCase in cases {
            XCTAssertThrowsError(try controller.configure(RealtimeVideoFormat(
                width: 832, height: 1472, fps: 24,
                minimumBitrate: testCase.minimum,
                maximumBitrate: testCase.maximum
            ))) { error in
                XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
            }
        }
        XCTAssertTrue(rtcManager.encodingConfigurations.isEmpty)
    }

    func testConfigureMatchesEveryOfficialReference() throws {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)
        let cases = [
            (width: 160, height: 120, fps: 15, minimum: 65, maximum: 130),
            (width: 120, height: 120, fps: 15, minimum: 50, maximum: 100),
            (width: 320, height: 180, fps: 15, minimum: 140, maximum: 280),
            (width: 180, height: 180, fps: 15, minimum: 100, maximum: 200),
            (width: 240, height: 180, fps: 15, minimum: 120, maximum: 240),
            (width: 320, height: 240, fps: 15, minimum: 200, maximum: 400),
            (width: 240, height: 240, fps: 15, minimum: 140, maximum: 280),
            (width: 424, height: 240, fps: 15, minimum: 220, maximum: 440),
            (width: 640, height: 360, fps: 15, minimum: 400, maximum: 800),
            (width: 360, height: 360, fps: 15, minimum: 260, maximum: 520),
            (width: 640, height: 360, fps: 30, minimum: 600, maximum: 1200),
            (width: 360, height: 360, fps: 30, minimum: 400, maximum: 800),
            (width: 480, height: 360, fps: 15, minimum: 320, maximum: 640),
            (width: 480, height: 360, fps: 30, minimum: 490, maximum: 980),
            (width: 640, height: 480, fps: 15, minimum: 500, maximum: 1000),
            (width: 480, height: 480, fps: 15, minimum: 400, maximum: 800),
            (width: 640, height: 480, fps: 30, minimum: 750, maximum: 1500),
            (width: 480, height: 480, fps: 30, minimum: 600, maximum: 1200),
            (width: 848, height: 480, fps: 15, minimum: 610, maximum: 1220),
            (width: 848, height: 480, fps: 30, minimum: 930, maximum: 1860),
            (width: 640, height: 480, fps: 10, minimum: 400, maximum: 800),
            (width: 1280, height: 720, fps: 15, minimum: 1130, maximum: 2260),
            (width: 1280, height: 720, fps: 30, minimum: 1710, maximum: 3420),
            (width: 960, height: 720, fps: 15, minimum: 910, maximum: 1820),
            (width: 960, height: 720, fps: 30, minimum: 1380, maximum: 2760),
            (width: 1920, height: 1080, fps: 15, minimum: 2080, maximum: 4160),
            (width: 1920, height: 1080, fps: 30, minimum: 3150, maximum: 6300),
            (width: 1920, height: 1080, fps: 60, minimum: 4780, maximum: 6500)
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

    func testConfigureInterpolatesAndExtrapolatesUploadBitrate() throws {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)
        let cases = [
            (width: 1920, height: 1080, fps: 30, minimum: 3150, maximum: 6300),
            (width: 1920, height: 1080, fps: 24, minimum: 2722, maximum: 5444),
            (width: 832, height: 1472, fps: 24, minimum: 1805, maximum: 3611),
            (width: 1472, height: 832, fps: 24, minimum: 1805, maximum: 3611),
            (width: 1024, height: 1920, fps: 30, minimum: 3016, maximum: 6031),
            (width: 1024, height: 1920, fps: 24, minimum: 2606, maximum: 5212),
            (width: 1024, height: 768, fps: 30, minimum: 1516, maximum: 3033),
            (width: 1024, height: 768, fps: 24, minimum: 1310, maximum: 2620),
            (width: 1920, height: 1080, fps: 120, minimum: 9560, maximum: 13000),
            (width: 3840, height: 2160, fps: 30, minimum: 12600, maximum: 25200),
            (width: 120, height: 120, fps: 30, minimum: 77, maximum: 154),
            (width: 1920, height: 1080, fps: 1, minimum: 166, maximum: 333),
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

    func testBitrateRemainsOrderedAndMonotonicAcrossFrameRateBoundaries() throws {
        let rtcManager = RtcManagingStub()
        let controller = EncodingController(rtcManager: rtcManager)

        for (width, height) in [(120, 120), (320, 240), (832, 1472), (1920, 1080), (3840, 2160)] {
            var previousMinimum = 0
            var previousMaximum = 0
            for fps in [1, 9, 10, 11, 14, 15, 16, 24, 29, 30, 31, 59, 60, 61, 120] {
                try controller.configure(RealtimeVideoFormat(width: width, height: height, fps: fps))
                let configuration = try XCTUnwrap(rtcManager.encodingConfigurations.last)
                XCTAssertGreaterThan(configuration.minimumBitrate, 0)
                XCTAssertGreaterThan(configuration.maximumBitrate, configuration.minimumBitrate)
                XCTAssertGreaterThanOrEqual(configuration.minimumBitrate, previousMinimum)
                XCTAssertGreaterThanOrEqual(configuration.maximumBitrate, previousMaximum)
                previousMinimum = configuration.minimumBitrate
                previousMaximum = configuration.maximumBitrate
            }
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
