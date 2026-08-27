import CoreGraphics
import Foundation
import XCTest
@testable import XmaxSDK

final class MediaSourceControllerTests: XCTestCase {
    func testPrepareResolvesRotatedSizeAndConfiguresAudioVideo() async throws {
        let components = makeComponents(hasAudio: true)
        let fileURL = URL(fileURLWithPath: "/tmp/source.mp4")

        let configuration = try await components.controller.prepare(
            fileURL: fileURL,
            videoFormat: nil
        )

        XCTAssertEqual(
            configuration,
            MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: true
            )
        )
        XCTAssertEqual(
            components.mediaService.requestedSizes,
            [CGSize(width: 1_080, height: 1_920)]
        )
        XCTAssertEqual(
            components.videoSource.configurations,
            [
                .init(
                    fileURL: fileURL,
                    outputWidth: 832,
                    outputHeight: 1_472,
                    rotation: .rotation90,
                    frameRate: 24
                )
            ]
        )
        XCTAssertEqual(components.audioSource.fileURLs, [fileURL])
        XCTAssertTrue(components.controller.hasAudio)
    }

    func testStartRestartAndStopUseSharedAudioVideoTimeline() async throws {
        let components = makeComponents(hasAudio: true)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: videoFormat
        )

        try await components.controller.start()
        try await components.controller.restart(from: 750_000)
        await components.controller.stop()

        XCTAssertEqual(components.audioManager.calls, [
            .start,
            .flush,
            .stop
        ])
        XCTAssertEqual(
            components.videoSource.startedTimelines,
            components.audioSource.startedTimelines
        )
        XCTAssertEqual(
            components.videoSource.restartedTimelines,
            components.audioSource.restartedTimelines
        )
        XCTAssertEqual(
            components.videoSource.restartedTimelines.first?.mediaStartUs,
            750_000
        )
        XCTAssertEqual(components.videoSource.stopCount, 1)
        XCTAssertEqual(components.audioSource.stopCount, 1)
        XCTAssertFalse(components.controller.hasAudio)
    }

    func testSilentVideoDoesNotStartAudioPlaybackOrDecoder() async throws {
        let components = makeComponents(hasAudio: false)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4"),
            videoFormat: nil
        )

        try await components.controller.start()

        XCTAssertTrue(components.audioManager.calls.isEmpty)
        XCTAssertTrue(components.audioSource.startedTimelines.isEmpty)
        XCTAssertEqual(components.videoSource.startedTimelines.count, 1)
    }

    func testLocalAudioPreviewControlDoesNotStopAudioDecoder() async throws {
        let components = makeComponents(hasAudio: true)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )
        try await components.controller.start()

        try await components.controller.setLocalAudioPreviewEnabled(false)
        try await components.controller.setLocalAudioPreviewEnabled(true)

        XCTAssertEqual(components.audioManager.calls, [
            .start,
            .setPlaybackEnabled(false),
            .setPlaybackEnabled(true)
        ])
        XCTAssertEqual(components.audioSource.stopCount, 0)
    }
}

private extension MediaSourceControllerTests {
    struct Components {
        let controller: MediaSourceController
        let mediaService: MediaServicingStub
        let audioManager: AudioManagingStub
        let videoSource: VideoSourceControllingStub
        let audioSource: AudioSourceControllingStub
    }

    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeComponents(hasAudio: Bool) -> Components {
        let metadataManager = MediaFileMetadataManagingStub(
            metadata: MediaFileMetadata(
                width: 1_920,
                height: 1_080,
                rotation: .rotation90,
                durationUs: 2_000_000,
                hasAudio: hasAudio
            )
        )
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 832, height: 1_472)
        )
        let audioManager = AudioManagingStub()
        let videoSource = VideoSourceControllingStub()
        let audioSource = AudioSourceControllingStub()
        let controller = MediaSourceController(
            metadataManager: metadataManager,
            audioManager: audioManager,
            mediaService: mediaService,
            videoSourceController: videoSource,
            audioSourceController: audioSource
        )
        return Components(
            controller: controller,
            mediaService: mediaService,
            audioManager: audioManager,
            videoSource: videoSource,
            audioSource: audioSource
        )
    }
}

private final class MediaFileMetadataManagingStub:
    MediaFileMetadataManaging,
    Sendable {

    // 测试配置
    private let metadata: MediaFileMetadata

    init(metadata: MediaFileMetadata) {
        self.metadata = metadata
    }

    func readMetadata(fileURL: URL) async throws -> MediaFileMetadata {
        metadata
    }
}

private enum AudioManagingCall: Equatable {
    case start
    case flush
    case setPlaybackEnabled(Bool)
    case stop
}

private final class AudioManagingStub: AudioManaging, @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [AudioManagingCall] = []

    var calls: [AudioManagingCall] {
        lock.withLock { storedCalls }
    }

    func start() async throws {
        lock.withLock {
            storedCalls.append(.start)
        }
    }

    func write(frame: AudioFrame) {}

    func flush() async throws {
        lock.withLock {
            storedCalls.append(.flush)
        }
    }

    func setPlaybackEnabled(_ enabled: Bool) async throws {
        lock.withLock {
            storedCalls.append(.setPlaybackEnabled(enabled))
        }
    }

    func stop() async {
        lock.withLock {
            storedCalls.append(.stop)
        }
    }
}

private struct VideoSourceConfigurationCall: Equatable {
    let fileURL: URL
    let outputWidth: Int
    let outputHeight: Int
    let rotation: VideoRotation
    let frameRate: Int
}

private final class VideoSourceControllingStub:
    VideoSourceControlling,
    @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedConfigurations: [VideoSourceConfigurationCall] = []
    private var storedStartedTimelines: [MediaTimeline] = []
    private var storedRestartedTimelines: [MediaTimeline] = []
    private var storedStopCount = 0

    var configurations: [VideoSourceConfigurationCall] {
        lock.withLock { storedConfigurations }
    }

    var startedTimelines: [MediaTimeline] {
        lock.withLock { storedStartedTimelines }
    }

    var restartedTimelines: [MediaTimeline] {
        lock.withLock { storedRestartedTimelines }
    }

    var stopCount: Int {
        lock.withLock { storedStopCount }
    }

    func configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int
    ) throws {
        lock.withLock {
            storedConfigurations.append(
                VideoSourceConfigurationCall(
                    fileURL: fileURL,
                    outputWidth: outputWidth,
                    outputHeight: outputHeight,
                    rotation: rotation,
                    frameRate: frameRate
                )
            )
        }
    }

    func start(timeline: MediaTimeline) async throws {
        lock.withLock {
            storedStartedTimelines.append(timeline)
        }
    }

    func restart(timeline: MediaTimeline) async throws {
        lock.withLock {
            storedRestartedTimelines.append(timeline)
        }
    }

    func stop() {
        lock.withLock {
            storedStopCount += 1
        }
    }
}

private final class AudioSourceControllingStub:
    AudioSourceControlling,
    @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedFileURLs: [URL] = []
    private var storedStartedTimelines: [MediaTimeline] = []
    private var storedRestartedTimelines: [MediaTimeline] = []
    private var storedStopCount = 0

    var fileURLs: [URL] {
        lock.withLock { storedFileURLs }
    }

    var startedTimelines: [MediaTimeline] {
        lock.withLock { storedStartedTimelines }
    }

    var restartedTimelines: [MediaTimeline] {
        lock.withLock { storedRestartedTimelines }
    }

    var stopCount: Int {
        lock.withLock { storedStopCount }
    }

    func configure(fileURL: URL) throws {
        lock.withLock {
            storedFileURLs.append(fileURL)
        }
    }

    func start(timeline: MediaTimeline) async throws {
        lock.withLock {
            storedStartedTimelines.append(timeline)
        }
    }

    func restart(timeline: MediaTimeline) async throws {
        lock.withLock {
            storedRestartedTimelines.append(timeline)
        }
    }

    func stop() {
        lock.withLock {
            storedStopCount += 1
        }
    }
}
