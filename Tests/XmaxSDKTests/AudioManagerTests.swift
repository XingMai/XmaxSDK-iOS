import AVFoundation
import Foundation
import XCTest
@testable import XmaxSDK

final class AudioManagerTests: XCTestCase {
    func testStartIsIdempotentAndWriteForwardsPCMData() async throws {
        let controller = AudioPlaybackControllerStub()
        let manager = AudioManager(playbackFactory: { controller })
        let frame = AudioFrame(
            data: Data(repeating: 7, count: 960),
            timestampUs: 0
        )

        try await manager.start()
        try await manager.start()
        manager.write(frame: frame)

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.enqueuedData, [frame.data])
    }

    func testWriteBeforeStartIsIgnored() {
        let controller = AudioPlaybackControllerStub()
        let manager = AudioManager(playbackFactory: { controller })

        manager.write(frame: AudioFrame(
            data: Data(repeating: 0, count: 960),
            timestampUs: 0
        ))

        XCTAssertEqual(controller.enqueuedData, [])
    }

    func testFlushAndStopForwardLifecycleAndStopIsIdempotent() async throws {
        let controller = AudioPlaybackControllerStub()
        let manager = AudioManager(playbackFactory: { controller })

        try await manager.start()
        try await manager.flush()
        await manager.stop()
        await manager.stop()
        manager.write(frame: AudioFrame(
            data: Data(repeating: 0, count: 960),
            timestampUs: 0
        ))

        XCTAssertEqual(controller.flushCount, 1)
        XCTAssertEqual(controller.stopCount, 1)
        XCTAssertEqual(controller.enqueuedData, [])
    }

    func testDisabledPlaybackFlushesAndIgnoresFramesUntilEnabled()
        async throws {
        let controller = AudioPlaybackControllerStub()
        let manager = AudioManager(playbackFactory: { controller })
        let firstFrame = AudioFrame(
            data: Data(repeating: 1, count: 960),
            timestampUs: 0
        )
        let secondFrame = AudioFrame(
            data: Data(repeating: 2, count: 960),
            timestampUs: 10_000
        )

        try await manager.start()
        manager.write(frame: firstFrame)
        try await manager.setPlaybackEnabled(false)
        manager.write(frame: secondFrame)
        try await manager.setPlaybackEnabled(true)
        manager.write(frame: secondFrame)

        XCTAssertEqual(controller.flushCount, 1)
        XCTAssertEqual(
            controller.enqueuedData,
            [firstFrame.data, secondFrame.data]
        )
    }

    func testStartMapsPlatformFailureToMediaError() async {
        let manager = AudioManager(playbackFactory: {
            throw NSError(
                domain: "AudioManagerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "audio unavailable"]
            )
        })

        do {
            try await manager.start()
            XCTFail("Expected audio start to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(code: .mediaError, message: "audio unavailable")
            )
        }
    }

    func testSystemBufferUsesPCM16FrameCount() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48_000,
            channels: 1,
            interleaved: true
        ))
        let data = Data(repeating: 1, count: 960)

        let buffer = try SystemAudioPlaybackController.makeBuffer(
            data: data,
            format: format
        )

        XCTAssertEqual(buffer.frameLength, 480)
        XCTAssertEqual(
            buffer.mutableAudioBufferList.pointee.mBuffers.mDataByteSize,
            960
        )
    }

    func testSystemBufferRejectsPartialPCM16Sample() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48_000,
            channels: 1,
            interleaved: true
        ))

        XCTAssertThrowsError(
            try SystemAudioPlaybackController.makeBuffer(
                data: Data(repeating: 0, count: 3),
                format: format
            )
        )
    }
}

private final class AudioPlaybackControllerStub: AudioPlaybackControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var enqueued: [Data] = []
    private var flushes = 0
    private var stops = 0

    var startCount: Int {
        lock.withLock { starts }
    }

    var enqueuedData: [Data] {
        lock.withLock { enqueued }
    }

    var flushCount: Int {
        lock.withLock { flushes }
    }

    var stopCount: Int {
        lock.withLock { stops }
    }

    func start() throws {
        lock.withLock {
            starts += 1
        }
    }

    func enqueue(_ data: Data) throws {
        lock.withLock {
            enqueued.append(data)
        }
    }

    func flush() throws {
        lock.withLock {
            flushes += 1
        }
    }

    func stop() {
        lock.withLock {
            stops += 1
        }
    }
}
