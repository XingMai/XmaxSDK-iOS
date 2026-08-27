@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit

/// 定义基于统一媒体时间轴的文件音视频输出能力。
protocol VideoPlayerControlling: Sendable {

    /// 配置本地视频文件及最终 RTC 输出格式。
    @MainActor
    func configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool
    ) async throws

    /// 开始本地预览和 RTC 音视频帧输出。
    @MainActor
    func start() async throws

    /// 静音或恢复本地音频预览，不影响播放器和 RTC 音频帧输出。
    @MainActor
    func setLocalAudioPreviewMuted(_ muted: Bool)

    /// 设置本地音频预览音量。
    @MainActor
    func setLocalAudioVolume(_ volume: Float)

    /// 将解码后的视频画面绑定到 SDK 视频视图。
    @MainActor
    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws

    /// 从 SDK 视频视图解除解码画面。
    @MainActor
    func detachPreview(from view: UIView)

    /// 停止解码并等待全部 reader 在所属任务内安全退出。
    @MainActor
    func stop() async
}

/// 将解码帧投递到当前绑定的 SDK 视频视图。
@MainActor
private final class DecodedVideoPreviewPresenter {

    // 预览资源
    private weak var view: XmaxVideoView?
    private var contentMode = VideoContentMode.fill

    func attach(
        to view: XmaxVideoView,
        contentMode: VideoContentMode
    ) {
        self.view = view
        self.contentMode = contentMode
        view.prepareDecodedVideoPreview(contentMode: contentMode)
    }

    func detach(from view: XmaxVideoView) {
        view.clearDecodedVideoPreview()
        if self.view === view {
            self.view = nil
        }
    }

    func display(_ frame: VideoFrame) {
        view?.displayDecodedVideoFrame(frame, contentMode: contentMode)
    }

    func clear() {
        view?.clearDecodedVideoPreview()
        view = nil
    }
}

/// 合并主线程来不及显示的帧，只保留最新的视频预览帧。
private final class DecodedVideoPreviewDispatcher: @unchecked Sendable {

    // 渲染组件
    private let presenter: DecodedVideoPreviewPresenter

    // 并发状态
    private let lock = NSLock()
    private var pendingFrame: VideoFrame?
    private var isDeliveryScheduled = false

    init(presenter: DecodedVideoPreviewPresenter) {
        self.presenter = presenter
    }

    func enqueue(_ frame: VideoFrame) {
        let shouldSchedule = lock.withLock { () -> Bool in
            pendingFrame = frame
            guard !isDeliveryScheduled else { return false }
            isDeliveryScheduled = true
            return true
        }
        if shouldSchedule {
            scheduleDelivery()
        }
    }

    func reset() {
        lock.withLock {
            pendingFrame = nil
        }
    }

    private func scheduleDelivery() {
        Task { @MainActor [weak self] in
            self?.deliverLatestFrame()
        }
    }

    @MainActor
    private func deliverLatestFrame() {
        let frame = lock.withLock { () -> VideoFrame? in
            let frame = pendingFrame
            pendingFrame = nil
            return frame
        }
        if let frame {
            presenter.display(frame)
        }

        let shouldScheduleAgain = lock.withLock { () -> Bool in
            if pendingFrame == nil {
                isDeliveryScheduled = false
                return false
            }
            return true
        }
        if shouldScheduleAgain {
            scheduleDelivery()
        }
    }
}

/// 使用 AVAssetReader 解码共享时间轴上的本地音视频帧。
@MainActor
final class VideoPlayerController: VideoPlayerControlling {

    private struct PlaybackConfiguration: Sendable {
        let fileURL: URL
        let outputWidth: Int
        let outputHeight: Int
        let rotation: VideoRotation
        let frameRate: Int
        let hasAudio: Bool
        let durationSeconds: Double
    }

    // 帧监听
    private let videoFrameListener: MediaVideoFrameListener
    private let audioFrameListener: MediaAudioFrameListener
    private let errorListener: XmaxErrorListener

    // 平台资源
    private let audioPreviewPlayer = LocalAudioPreviewPlayer()
    private let previewPresenter = DecodedVideoPreviewPresenter()
    private lazy var previewDispatcher = DecodedVideoPreviewDispatcher(
        presenter: previewPresenter
    )

    // 媒体配置
    private var configuration: PlaybackConfiguration?

    // 运行状态
    private var playbackTask: Task<Void, Never>?

    init(
        videoFrameListener: @escaping MediaVideoFrameListener,
        audioFrameListener: @escaping MediaAudioFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.videoFrameListener = videoFrameListener
        self.audioFrameListener = audioFrameListener
        self.errorListener = errorListener
    }

    /// 校验文件并保存统一解码所需的媒体配置。
    func configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool
    ) async throws {
        guard fileURL.isFileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              outputWidth > 0,
              outputHeight > 0,
              outputWidth.isMultiple(of: 2),
              outputHeight.isMultiple(of: 2),
              frameRate > 0,
              configuration == nil,
              playbackTask == nil else {
            throw Self.mediaError("Video player configuration is invalid")
        }

        let asset = AVURLAsset(url: fileURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw Self.mediaError("The media file does not contain a video track")
        }
        if hasAudio {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else {
                throw Self.mediaError("The media file does not contain an audio track")
            }
        }
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw Self.mediaError("The media file has an invalid duration")
        }

        configuration = PlaybackConfiguration(
            fileURL: fileURL,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            rotation: rotation,
            frameRate: frameRate,
            hasAudio: hasAudio,
            durationSeconds: durationSeconds
        )
    }

    /// 启动共用时间轴的音视频解码任务。
    func start() async throws {
        guard let configuration, playbackTask == nil else {
            throw Self.mediaError("Configure the video player before starting it")
        }

        if configuration.hasAudio {
            audioPreviewPlayer.start()
            audioPreviewPlayer.setMuted(false)
        }
        let timeline = MediaPlaybackTimeline(
            mediaDurationSeconds: configuration.durationSeconds
        )
        let videoListener = videoFrameListener
        let audioListener = audioFrameListener
        let errorListener = errorListener
        let audioPreviewPlayer = audioPreviewPlayer
        let previewDispatcher = previewDispatcher
        playbackTask = Task.detached(priority: .userInitiated) {
            do {
                try await Self.play(
                    configuration: configuration,
                    timeline: timeline,
                    videoHandler: { frame in
                        previewDispatcher.enqueue(frame)
                        try videoListener(frame)
                    },
                    audioHandler: { frame in
                        audioPreviewPlayer.enqueue(frame)
                        try audioListener(frame)
                    }
                )
            } catch is CancellationError {
                return
            } catch {
                errorListener(XmaxError.from(error))
            }
        }
    }

    /// 切换本地 PCM 静音状态；播放时间轴和 RTC 推帧保持连续。
    func setLocalAudioPreviewMuted(_ muted: Bool) {
        audioPreviewPlayer.setMuted(muted)
    }

    /// 更新本地 PCM 播放音量。
    func setLocalAudioVolume(_ volume: Float) {
        audioPreviewPlayer.setVolume(volume)
    }

    /// 绑定 SDK 内部的解码视频渲染视图。
    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        guard let videoView = view as? XmaxVideoView else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "File video tracks require an XmaxVideoView"
            )
        }
        previewPresenter.attach(to: videoView, contentMode: contentMode)
    }

    /// 解除 SDK 内部的解码视频渲染视图。
    func detachPreview(from view: UIView) {
        guard let videoView = view as? XmaxVideoView else { return }
        previewPresenter.detach(from: videoView)
    }

    /// 取消任务并等待音视频 reader 退出后释放配置。
    func stop() async {
        let task = playbackTask
        playbackTask = nil
        task?.cancel()
        await task?.value
        await audioPreviewPlayer.stop()
        previewDispatcher.reset()
        previewPresenter.clear()
        configuration = nil
    }
}

private extension VideoPlayerController {
    typealias VideoHandler = @Sendable (VideoFrame) throws -> Void
    typealias AudioHandler = @Sendable (AudioFrame) throws -> Void

    private nonisolated static func play(
        configuration: PlaybackConfiguration,
        timeline: MediaPlaybackTimeline,
        videoHandler: @escaping VideoHandler,
        audioHandler: @escaping AudioHandler
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await produceVideoFrames(
                    configuration: configuration,
                    timeline: timeline,
                    handler: videoHandler
                )
            }
            if configuration.hasAudio {
                group.addTask {
                    try await produceAudioFrames(
                        configuration: configuration,
                        timeline: timeline,
                        handler: audioHandler
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    private nonisolated static func produceVideoFrames(
        configuration: PlaybackConfiguration,
        timeline: MediaPlaybackTimeline,
        handler: @escaping VideoHandler
    ) async throws {
        let frameIntervalSeconds = 1 / Double(configuration.frameRate)
        let frameIntervalNanoseconds = UInt64(
            frameIntervalSeconds * 1_000_000_000
        )
        var loopIndex = 0

        while true {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: configuration.fileURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw mediaError("The media file does not contain a video track")
            }
            let timeRange = try await track.load(.timeRange)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw mediaError("The media video track cannot be decoded")
            }
            reader.add(output)
            guard reader.startReading() else {
                throw mediaError(
                    reader.error?.localizedDescription ??
                        "The media video track could not start decoding"
                )
            }
            defer {
                if reader.status == .reading {
                    reader.cancelReading()
                }
            }

            var yieldedFrame = false
            var lastYieldedSeconds = -Double.infinity
            while reader.status == .reading {
                try Task.checkCancellation()
                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    break
                }
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let relativeTime = CMTimeSubtract(pts, timeRange.start)
                let relativeSeconds = max(0, CMTimeGetSeconds(relativeTime))
                guard relativeSeconds.isFinite,
                      relativeSeconds - lastYieldedSeconds >=
                        frameIntervalSeconds * 0.75,
                      let pixelBuffer = CMSampleBufferGetImageBuffer(
                          sampleBuffer
                      ) else {
                    continue
                }

                let target = timeline.target(
                    loopIndex: loopIndex,
                    mediaOffsetSeconds: relativeSeconds
                )
                let now = DispatchTime.now().uptimeNanoseconds
                if now > target, now - target > frameIntervalNanoseconds {
                    continue
                }
                let frame = try NV12VideoFrameConverter.convert(
                    pixelBuffer: pixelBuffer,
                    outputWidth: configuration.outputWidth,
                    outputHeight: configuration.outputHeight,
                    rotation: configuration.rotation,
                    timestampUs: monotonicTimestampUs()
                )
                try await sleep(untilNanoseconds: target)
                try handler(frame)
                yieldedFrame = true
                lastYieldedSeconds = relativeSeconds
            }

            if reader.status == .failed {
                throw mediaError(
                    reader.error?.localizedDescription ??
                        "The media video track failed while decoding"
                )
            }
            guard yieldedFrame else {
                throw mediaError("The media file produced no video frames")
            }
            loopIndex += 1
            let nextLoop = timeline.target(
                loopIndex: loopIndex,
                mediaOffsetSeconds: 0
            )
            try await sleep(untilNanoseconds: nextLoop)
        }
    }

    private nonisolated static func produceAudioFrames(
        configuration: PlaybackConfiguration,
        timeline: MediaPlaybackTimeline,
        handler: @escaping AudioHandler
    ) async throws {
        var loopIndex = 0
        while true {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: configuration.fileURL)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else {
                throw mediaError("The media file does not contain an audio track")
            }
            let timeRange = try await track.load(.timeRange)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: [track],
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: AudioFrame.sampleRate,
                    AVNumberOfChannelsKey: AudioFrame.channelCount,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw mediaError("The media audio track cannot be decoded")
            }
            reader.add(output)
            guard reader.startReading() else {
                throw mediaError(
                    reader.error?.localizedDescription ??
                        "The media audio track could not start decoding"
                )
            }
            defer {
                if reader.status == .reading {
                    reader.cancelReading()
                }
            }

            var packetizer = PCMFramePacketizer(
                totalSamples: timeline.cycleSampleCount
            )
            while reader.status == .reading {
                try Task.checkCancellation()
                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    break
                }
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let relativeTime = CMTimeSubtract(pts, timeRange.start)
                let relativeSeconds = max(0, CMTimeGetSeconds(relativeTime))
                guard relativeSeconds.isFinite else { continue }
                let startSample = Int(
                    (relativeSeconds * Double(AudioFrame.sampleRate)).rounded()
                )
                packetizer.append(
                    try pcmData(from: sampleBuffer),
                    at: startSample
                )
                try await emitAudioFrames(
                    packetizer: &packetizer,
                    loopIndex: loopIndex,
                    timeline: timeline,
                    handler: handler
                )
            }

            if reader.status == .failed {
                throw mediaError(
                    reader.error?.localizedDescription ??
                        "The media audio track failed while decoding"
                )
            }
            packetizer.finishWithSilence()
            try await emitAudioFrames(
                packetizer: &packetizer,
                loopIndex: loopIndex,
                timeline: timeline,
                handler: handler
            )
            loopIndex += 1
        }
    }

    nonisolated static func emitAudioFrames(
        packetizer: inout PCMFramePacketizer,
        loopIndex: Int,
        timeline: MediaPlaybackTimeline,
        handler: @escaping AudioHandler
    ) async throws {
        while let packet = packetizer.nextFrame() {
            let target = timeline.target(
                loopIndex: loopIndex,
                sampleOffset: packet.sampleOffset
            )
            let now = DispatchTime.now().uptimeNanoseconds
            if now < target {
                try await sleep(untilNanoseconds: target)
            } else if now - target > 30_000_000 {
                continue
            }
            try handler(
                AudioFrame(
                    data: packet.data,
                    timestampUs: monotonicTimestampUs()
                )
            )
        }
    }

    nonisolated static func pcmData(
        from sampleBuffer: CMSampleBuffer
    ) throws -> Data {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return Data()
        }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return kCMBlockBufferBadCustomBlockSourceErr
            }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: length,
                destination: baseAddress
            )
        }
        guard status == kCMBlockBufferNoErr else {
            throw mediaError("The decoded PCM data could not be read")
        }
        return data
    }

    nonisolated static func monotonicTimestampUs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000)
    }

    nonisolated static func sleep(untilNanoseconds target: UInt64) async throws {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < target else { return }
        try await Task.sleep(nanoseconds: target - now)
    }

    nonisolated static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
