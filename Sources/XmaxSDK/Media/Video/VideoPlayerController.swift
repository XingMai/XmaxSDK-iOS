@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import UIKit

/// 定义单一播放器时间线的本地预览和 RTC 音视频输出能力。
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

    /// 启用或暂停系统播放器的本地音频。
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

/// 使用单一 AVPlayer 时间线协调本地视频预览和 RTC 音视频帧输出。
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
    private let player = AVPlayer()
    private let frameQueue = DispatchQueue(
        label: "ai.xmax.sdk.video-player-frame",
        qos: .userInteractive
    )
    private var playerItem: AVPlayerItem?
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
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
    }

    /// 配置文件播放器、视频帧输出和音频处理 Tap。
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
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: Self.pixelBufferAttributes
        )
        item.add(output)

        var resolvedAudioTap: PlayerAudioTap?
        if hasAudio {
            resolvedAudioTap = try await makeAudioTap(
                asset: asset,
                playerItem: item
            )
        }

        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        outputRotation = rotation
        self.frameRate = frameRate
        videoOutput = output
        audioTap = resolvedAudioTap
        playerItem = item
        player.replaceCurrentItem(with: item)
        observeEnd(of: item)
        isConfigured = true
    }

    /// 从当前文件位置开始播放并输出音视频帧。
    func start() throws {
        guard isConfigured, playerItem != nil else {
            throw Self.mediaError("Configure the video player before starting it")
        }
        startDisplayLink()
        player.play()
        isPlaying = true
    }

    /// 设置本地播放器静音状态，不影响前置音频 Tap 的 RTC 帧输出。
    func setLocalAudioPreviewEnabled(_ enabled: Bool) {
        player.isMuted = !enabled
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
        videoView.displayPlayer(player, contentMode: contentMode)
    }

    /// 从 SDK 视频视图解除 AVPlayerLayer。
    func detachPreview(from view: UIView) {
        guard let videoView = view as? XmaxVideoView else {
            return
        }
        videoView.clearPlayer(player)
        if previewView === videoView {
            previewView = nil
        }
    }

    /// 停止播放器并释放输出、Tap 和渲染资源。
    func stop() {
        isConfigured = false
        isPlaying = false
        isFrameConversionPending = false
        displayLink?.invalidate()
        displayLink = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerItem = nil
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
    func makeAudioTap(
        asset: AVAsset,
        playerItem: AVPlayerItem
    ) async throws -> PlayerAudioTap {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw Self.mediaError("The media file does not contain an audio track")
        }

        let tap = try PlayerAudioTap(
            frameListener: audioFrameListener,
            errorListener: errorListener
        )
        let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
        parameters.audioTapProcessor = tap.takeProcessingTap()
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [parameters]
        playerItem.audioMix = audioMix
        return tap
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
        guard isConfigured, playerItem === item else {
            return
        }
        await seek(to: .zero)
        audioTap?.reset()
        player.play()
        isPlaying = true
    }

    func seek(to time: CMTime) async {
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
