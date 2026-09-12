import XCTest
@testable import XmaxSDK

final class CameraPerformanceProbeTests: XCTestCase {
    func testCaptureOnlyMeasuresTheSameTimestampToCallbackInterval() {
        XCTAssertEqual(
            CameraPerformanceProbe.deliveryMilliseconds(timestampUs: 1000000, callbackEntry: 1034320000),
            34.32
        )
        XCTAssertNil(CameraPerformanceProbe.deliveryMilliseconds(timestampUs: -1, callbackEntry: 0))
        XCTAssertNil(CameraPerformanceProbe.deliveryMilliseconds(timestampUs: Int64.max, callbackEntry: 0))
        XCTAssertNil(CameraPerformanceProbe.deliveryMilliseconds(timestampUs: 1000000, callbackEntry: 999999999))
    }

    func testSameFrameSegmentsAddUpToCaptureToPreviewLatency() throws {
        let timing = CameraPerformanceProbe.FrameTiming(
            capture: 1000000000,
            callbackEntry: 1029000000,
            conversionStart: 1030000000,
            conversionEnd: 1034000000
        )
        let sample = try XCTUnwrap(timing.sample(
            previewStart: 1039000000,
            previewEnd: 1040000000
        ))

        XCTAssertEqual(sample.delivery, 29)
        XCTAssertEqual(sample.preparation, 1)
        XCTAssertEqual(sample.conversion, 4)
        XCTAssertEqual(sample.scheduling, 5)
        XCTAssertEqual(sample.preview, 1)
        XCTAssertEqual(sample.total, 40)
    }

    func testAveragesUseCompleteSamplesAndPreserveTheirSum() throws {
        let first = CameraPerformanceProbe.FrameTiming(
            capture: 0, callbackEntry: 29000000, conversionStart: 30000000, conversionEnd: 34000000
        )
        let second = CameraPerformanceProbe.FrameTiming(
            capture: 50000000, callbackEntry: 68000000, conversionStart: 70000000, conversionEnd: 76000000
        )
        let samples = [
            try XCTUnwrap(first.sample(previewStart: 39000000, previewEnd: 40000000)),
            try XCTUnwrap(second.sample(previewStart: 78000000, previewEnd: 80000000))
        ]
        let totalAverage = samples.map(\.total).reduce(0, +) / Double(samples.count)
        let segmentAverages = [\CameraPerformanceProbe.PreviewSample.delivery, \.preparation, \.conversion, \.scheduling, \.preview].map { path in
            samples.map { $0[keyPath: path] }.reduce(0, +) / Double(samples.count)
        }

        XCTAssertEqual(totalAverage, 35)
        XCTAssertEqual(segmentAverages.reduce(0, +), totalAverage, accuracy: 0.000001)
        XCTAssertNil(first.sample(previewStart: 33000000, previewEnd: 40000000))
        XCTAssertNil(first.sample(previewStart: 39000000, previewEnd: 38000000))
    }

    func testInvalidCallbackOrderingIsExcluded() {
        let beforeCapture = CameraPerformanceProbe.FrameTiming(
            capture: 10, callbackEntry: 9, conversionStart: 20, conversionEnd: 30
        )
        let afterConversion = CameraPerformanceProbe.FrameTiming(
            capture: 10, callbackEntry: 21, conversionStart: 20, conversionEnd: 30
        )

        XCTAssertNil(beforeCapture.sample(previewStart: 40, previewEnd: 50))
        XCTAssertNil(afterConversion.sample(previewStart: 40, previewEnd: 50))
    }

    func testStatisticsAccumulateWithoutRetainingFrameSamples() {
        var statistics = CameraPerformanceProbe.Statistics()
        statistics.add(10)
        statistics.add(40)
        statistics.add(70)

        XCTAssertEqual(statistics.count, 3)
        XCTAssertEqual(statistics.totalMs / Double(statistics.count), 40)
    }

    func testPerformanceDisabledDoesNotStartSampling() {
        XmaxLogger.configure(options: .business)
        defer { XmaxLogger.configure(options: []) }
        let probe = CameraPerformanceProbe()
        probe.start(description: "Test", fps: 24)

        XCTAssertNil(probe.begin())
    }

    func testStopAndStaleFramesDoNotProduceMeasurements() {
        XmaxLogger.configure(options: .performance)
        defer { XmaxLogger.configure(options: []) }
        let probe = CameraPerformanceProbe()
        probe.start(description: "Test", fps: 24)

        XCTAssertNotNil(probe.begin())
        XCTAssertNil(probe.begin(frameTimestampUs: 0))
        probe.stop()
        XCTAssertNil(probe.begin())
    }
}
