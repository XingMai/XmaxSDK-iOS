import Foundation
import XCTest
@testable import XmaxSDK

final class PCMFramePacketizerTests: XCTestCase {
    func testPacketizesPCMIntoTenMillisecondFrames() {
        let firstFrame = pcmData(sample: 1, count: AudioFrame.samplesPerFrame)
        let secondFrame = pcmData(sample: 2, count: AudioFrame.samplesPerFrame)
        var packetizer = PCMFramePacketizer(
            totalSamples: AudioFrame.samplesPerFrame * 2
        )

        packetizer.append(firstFrame + secondFrame, at: 0)

        XCTAssertEqual(packetizer.nextFrame()?.data, firstFrame)
        XCTAssertEqual(packetizer.nextFrame()?.data, secondFrame)
        XCTAssertNil(packetizer.nextFrame())
    }

    func testFillsTimelineGapsAndTailWithSilence() {
        let samples = pcmData(sample: 7, count: AudioFrame.samplesPerFrame)
        let silence = pcmData(sample: 0, count: AudioFrame.samplesPerFrame)
        var packetizer = PCMFramePacketizer(
            totalSamples: AudioFrame.samplesPerFrame * 3
        )

        packetizer.append(samples, at: AudioFrame.samplesPerFrame)
        packetizer.finishWithSilence()

        XCTAssertEqual(packetizer.nextFrame()?.data, silence)
        XCTAssertEqual(packetizer.nextFrame()?.data, samples)
        XCTAssertEqual(packetizer.nextFrame()?.data, silence)
        XCTAssertNil(packetizer.nextFrame())
    }
}

private extension PCMFramePacketizerTests {
    func pcmData(sample: Int16, count: Int) -> Data {
        var samples = Array(repeating: sample, count: count)
        return samples.withUnsafeMutableBytes { Data($0) }
    }
}
