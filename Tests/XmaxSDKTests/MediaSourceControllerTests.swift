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
            [.init(fileURL: fileURL, rotation: .rotation90, frameRate: 24)]
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
        try await components.controller.restart()
        await components.controller.stop()

        XCTAssertEqual(components.audioProvider.calls, [
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

        XCTAssertTrue(components.audioProvider.calls.isEmpty)
        XCTAssertTrue(components.audioSource.startedTimelines.isEmpty)
        XCTAssertEqual(components.videoSource.startedTimelines.count, 1)
    }
}

private extension MediaSourceControllerTests {
    struct Components {
        let controller: MediaSourceController
        let mediaService: MediaServicingStub
        let audioProvider: AudioProvidingStub
        let videoSource: VideoSourceControllingStub
        let audioSource: AudioSourceControllingStub
    }

    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeComponents(hasAudio: Bool) -> Components {
        let metadataProvider = MediaFileMetadataProvidingStub(
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
        let audioProvider = AudioProvidingStub()
        let videoSource = VideoSourceControllingStub()
        let audioSource = AudioSourceControllingStub()
        let controller = MediaSourceController(
            metadataProvider: metadataProvider,
            audioProvider: audioProvider,
            mediaService: mediaService,
            videoSourceController: videoSource,
            audioSourceController: audioSource
        )
        return Components(
            controller: controller,
            mediaService: mediaService,
            audioProvider: audioProvider,
            videoSource: videoSource,
            audioSource: audioSource
        )
    }
}

private final class MediaFileMetadataProvidingStub:
    MediaFileMetadataProviding,
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

private enum AudioProvidingCall: Equatable {
    case start
    case flush
    case stop
}

private final class AudioProvidingStub: AudioProviding, @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [AudioProvidingCall] = []

    var calls: [AudioProvidingCall] {
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

    func stop() async {
        lock.withLock {
            storedCalls.append(.stop)
        }
    }
}

private struct VideoSourceConfigurationCall: Equatable {
    let fileURL: URL
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
        rotation: VideoRotation,
        frameRate: Int
    ) throws {
        lock.withLock {
            storedConfigurations.append(
                VideoSourceConfigurationCall(
                    fileURL: fileURL,
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
