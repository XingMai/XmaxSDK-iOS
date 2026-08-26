import Foundation
import XCTest
@testable import XmaxSDK

final class MediaModelTests: XCTestCase {
    func testMediaEnumRawValuesMatchCrossPlatformContract() {
        XCTAssertEqual(CameraPosition.allCases.map(\.rawValue), ["front", "back"])
        XCTAssertEqual(VideoContentMode.allCases.map(\.rawValue), ["fit", "fill"])
        XCTAssertEqual(
            VideoPixelFormat.allCases.map(\.rawValue),
            ["i420", "nv12", "nv21", "rgba", "bgra", "argb"]
        )
        XCTAssertEqual(
            VideoRotation.allCases.map(\.rawValue),
            [0, 90, 180, 270]
        )
    }

    func testAudioFrameUsesExternalAudioContract() {
        let frame = AudioFrame(
            data: Data(repeating: 1, count: 960),
            timestampUs: 10_000
        )

        XCTAssertEqual(AudioFrame.sampleRate, 48_000)
        XCTAssertEqual(AudioFrame.channelCount, 1)
        XCTAssertEqual(AudioFrame.samplesPerFrame, 480)
        XCTAssertEqual(frame.timestampUs, 10_000)
    }

    func testVideoFormatRejectsNonPositiveDimensions() {
        XCTAssertThrowsError(
            try VideoFormat(width: 0, height: 720, pixelFormat: .nv12)
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Video width and height must be positive integers"
                )
            )
        }
    }

    func testVideoFramePlaneUsesRemainingDataByDefault() throws {
        let plane = try VideoFramePlane(
            data: Data(repeating: 0, count: 24),
            stride: 8,
            byteOffset: 4
        )

        XCTAssertEqual(plane.byteOffset, 4)
        XCTAssertEqual(plane.byteLength, 20)
    }

    func testVideoFramePlaneRejectsOutOfBoundsRange() {
        XCTAssertThrowsError(
            try VideoFramePlane(
                data: Data(repeating: 0, count: 8),
                stride: 4,
                byteOffset: 4,
                byteLength: 5
            )
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Video frame plane range is invalid"
                )
            )
        }
    }

    func testVideoFrameStoresNeutralFrameData() throws {
        let format = try VideoFormat(
            width: 2,
            height: 2,
            pixelFormat: .bgra
        )
        let plane = try VideoFramePlane(
            data: Data(repeating: 255, count: 16),
            stride: 8
        )
        let frame = try VideoFrame(
            format: format,
            timestampUs: 33_333,
            planes: [plane],
            rotation: .rotation90
        )

        XCTAssertEqual(frame.format, format)
        XCTAssertNil(frame.bufferReuseID)
        XCTAssertEqual(frame.timestampUs, 33_333)
        XCTAssertEqual(frame.rotation, .rotation90)
        XCTAssertEqual(frame.planes, [plane])
    }

    func testVideoFrameRejectsNegativeTimestampAndEmptyPlanes() throws {
        let format = try VideoFormat(
            width: 1,
            height: 1,
            pixelFormat: .rgba
        )
        let plane = try VideoFramePlane(
            data: Data(repeating: 0, count: 4),
            stride: 4
        )

        XCTAssertThrowsError(
            try VideoFrame(
                format: format,
                timestampUs: -1,
                planes: [plane]
            )
        )
        XCTAssertThrowsError(
            try VideoFrame(
                format: format,
                timestampUs: 0,
                planes: []
            )
        )
    }
}
