@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import UIKit

/// 定义相互解耦的视频预览和音频输出能力。
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
    func start() throws

    /// 启用或静音系统播放器的本地音频。
    @MainActor
    func setLocalAudioPreviewEnabled(_ enabled: Bool)

    /// 将播放器画面绑定到 SDK 视频视图。
    @MainActor
    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws

    /// 从 SDK 视频视图解除播放器画面。
    @MainActor
    func detachPreview(from view: UIView)

    /// 停止播放器并释放全部输出资源。
    @MainActor
    func stop()
}

/// 使用独立 AVPlayer 分别承载视频预览和音频输出。
///
/// 视频播放器只包含视频轨道，避免 RTC 重配置共享音频会话时暂停本地画面；
/// 音频播放器负责本地声音和 RTC PCM 帧输出。
@MainActor
final class VideoPlayerController: NSObject, VideoPlayerControlling {

    private struct PixelBufferBox: @unchecked Sendable {
        let value: CVPixelBuffer
    }

    // 视频输出参数
    private static let pixelBufferAttributes: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]

    // 帧监听
    private let videoFrameListener: MediaVideoFrameListener
    private let audioFrameListener: MediaAudioFrameListener
    private let errorListener: XmaxErrorListener

    // 平台资源
    private let videoPlayer = AVPlayer()
    private let audioPlayer = AVPlayer()
    private let frameQueue = DispatchQueue(
        label: "ai.xmax.sdk.video-player-frame",
        qos: .userInteractive
    )
    private var videoPlayerItem: AVPlayerItem?
    private var audioPlayerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var audioTap: PlayerAudioTap?
    private var displayLink: CADisplayLink?
    private var endObserver: NSObjectProtocol?
    private weak var previewView: XmaxVideoView?

    // 视频配置
    private var outputWidth = 0
    private var outputHeight = 0
    private var outputRotation = VideoRotation.rotation0
    private var frameRate = 0

    // 运行状态
    private var isConfigured = false
    private var isFrameConversionPending = false
    private var audioPreviewVersion: UInt64 = 0
    private var isPlaying = false

    init(
        videoFrameListener: @escaping MediaVideoFrameListener,
        audioFrameListener: @escaping MediaAudioFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.videoFrameListener = videoFrameListener
        self.audioFrameListener = audioFrameListener
        self.errorListener = errorListener
        super.init()
        videoPlayer.actionAtItemEnd = .none
        videoPlayer.automaticallyWaitsToMinimizeStalling = false
        audioPlayer.actionAtItemEnd = .none
        audioPlayer.automaticallyWaitsToMinimizeStalling = true
    }

    /// 配置纯视频播放器、独立音频播放器和音频处理 Tap。
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
              frameRate > 0 else {
            throw Self.mediaError("Video player configuration is invalid")
        }
        guard !isConfigured else {
            throw Self.mediaError(
                "Stop the current video player before configuring another file"
            )
        }

        let asset = AVURLAsset(url: fileURL)
        let videoItem = try await makeVideoPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: Self.pixelBufferAttributes
        )
        videoItem.add(output)

        var resolvedAudioItem: AVPlayerItem?
        var resolvedAudioTap: PlayerAudioTap?
        if hasAudio {
            let audioPlayback = try await makeAudioPlayback(asset: asset)
            resolvedAudioItem = audioPlayback.item
            resolvedAudioTap = audioPlayback.tap
        }

        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        outputRotation = rotation
        self.frameRate = frameRate
        videoOutput = output
        audioTap = resolvedAudioTap
        videoPlayerItem = videoItem
        audioPlayerItem = resolvedAudioItem
        videoPlayer.replaceCurrentItem(with: videoItem)
        audioPlayer.replaceCurrentItem(with: resolvedAudioItem)
        observeEnd(of: videoItem)
        isConfigured = true
    }

    /// 从当前文件位置开始播放并输出音视频帧。
    func start() throws {
        guard isConfigured, videoPlayerItem != nil else {
            throw Self.mediaError("Configure the video player before starting it")
        }
        startDisplayLink()
        startPlayers()
        isPlaying = true
    }

    /// 设置独立音频播放器静音状态，不影响前置音频 Tap 的 RTC 帧输出。
    func setLocalAudioPreviewEnabled(_ enabled: Bool) {
        audioPreviewVersion &+= 1
        let version = audioPreviewVersion
        guard enabled else {
            audioPlayer.isMuted = true
            return
        }
        guard isConfigured, isPlaying, audioPlayerItem != nil else {
            audioPlayer.isMuted = false
            return
        }

        audioPlayer.isMuted = true
        audioPlayer.pause()
        audioPlayer.seek(
            to: videoPlayer.currentTime(),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isConfigured,
                      self.audioPreviewVersion == version else {
                    return
                }
                self.audioTap?.reset()
                self.audioPlayer.isMuted = false
                self.audioPlayer.play()
            }
        }
    }

    /// 将 AVPlayerLayer 绑定到 SDK 视频视图。
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
        previewView = videoView
        videoView.displayPlayer(videoPlayer, contentMode: contentMode)
    }

    /// 从 SDK 视频视图解除 AVPlayerLayer。
    func detachPreview(from view: UIView) {
        guard let videoView = view as? XmaxVideoView else {
            return
        }
        videoView.clearPlayer(videoPlayer)
        if previewView === videoView {
            previewView = nil
        }
    }

    /// 停止播放器并释放输出、Tap 和渲染资源。
    func stop() {
        isConfigured = false
        isPlaying = false
        isFrameConversionPending = false
        audioPreviewVersion &+= 1
        displayLink?.invalidate()
        displayLink = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        videoPlayer.pause()
        audioPlayer.pause()
        videoPlayer.replaceCurrentItem(with: nil)
        audioPlayer.replaceCurrentItem(with: nil)
        videoPlayerItem = nil
        audioPlayerItem = nil
        videoOutput = nil
        audioTap = nil
        previewView = nil
        outputWidth = 0
        outputHeight = 0
        outputRotation = .rotation0
        frameRate = 0
    }
}

private extension VideoPlayerController {
    struct AudioPlayback {
        let item: AVPlayerItem
        let tap: PlayerAudioTap
    }

    func makeVideoPlayerItem(asset: AVAsset) async throws -> AVPlayerItem {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceTrack = tracks.first else {
            throw Self.mediaError("The media file does not contain a video track")
        }
        let timeRange = try await sourceTrack.load(.timeRange)
        let preferredTransform = try await sourceTrack.load(
            .preferredTransform
        )
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw Self.mediaError("Failed to create the video playback track")
        }
        try track.insertTimeRange(
            timeRange,
            of: sourceTrack,
            at: .zero
        )
        track.preferredTransform = preferredTransform
        return AVPlayerItem(asset: composition)
    }

    func makeAudioPlayback(asset: AVAsset) async throws -> AudioPlayback {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceTrack = tracks.first else {
            throw Self.mediaError("The media file does not contain an audio track")
        }
        let timeRange = try await sourceTrack.load(.timeRange)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw Self.mediaError("Failed to create the audio playback track")
        }
        try track.insertTimeRange(
            timeRange,
            of: sourceTrack,
            at: .zero
        )
        let item = AVPlayerItem(asset: composition)

        let tap = try PlayerAudioTap(
            frameListener: audioFrameListener,
            errorListener: errorListener
        )
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap.takeProcessingTap()
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [parameters]
        item.audioMix = audioMix
        return AudioPlayback(item: item, tap: tap)
    }

    func observeEnd(of item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.restartAfterEnd(item: item)
            }
        }
    }

    func restartAfterEnd(item: AVPlayerItem) async {
        guard isConfigured, videoPlayerItem === item else {
            return
        }
        videoPlayer.pause()
        audioPlayer.pause()
        await seek(videoPlayer, to: .zero)
        if audioPlayerItem != nil {
            await seek(audioPlayer, to: .zero)
        }
        audioTap?.reset()
        startPlayers()
        isPlaying = true
    }

    func startPlayers() {
        if audioPlayerItem != nil {
            audioPlayer.play()
        }
        videoPlayer.play()
    }

    func seek(_ player: AVPlayer, to time: CMTime) async {
        await withCheckedContinuation { continuation in
            player.seek(
                to: time,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { _ in
                continuation.resume()
            }
        }
    }

    func startDisplayLink() {
        guard displayLink == nil else {
            return
        }
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(handleDisplayLink(_:))
        )
        displayLink.preferredFramesPerSecond = frameRate
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc func handleDisplayLink(_ displayLink: CADisplayLink) {
        guard isConfigured,
              isPlaying,
              !isFrameConversionPending,
              let videoOutput else {
            return
        }
        let itemTime = videoOutput.itemTime(
            forHostTime: displayLink.targetTimestamp
        )
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = videoOutput.copyPixelBuffer(
                  forItemTime: itemTime,
                  itemTimeForDisplay: nil
              ) else {
            return
        }

        let pixelBufferBox = PixelBufferBox(value: pixelBuffer)
        let width = outputWidth
        let height = outputHeight
        let rotation = outputRotation
        let timestampUs = Int64(
            DispatchTime.now().uptimeNanoseconds / 1_000
        )
        isFrameConversionPending = true
        frameQueue.async { [weak self] in
            do {
                let frame = try NV12VideoFrameConverter.convert(
                    pixelBuffer: pixelBufferBox.value,
                    outputWidth: width,
                    outputHeight: height,
                    rotation: rotation,
                    timestampUs: timestampUs
                )
                try self?.videoFrameListener(frame)
            } catch {
                self?.errorListener(XmaxError.from(error))
            }
            Task { @MainActor [weak self] in
                self?.isFrameConversionPending = false
            }
        }
    }

    static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
