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

    /// 暂停播放器并返回当前文件时间检查点。
    @MainActor
    func pause() -> Int64?

    /// 从指定文件时间重新播放并输出 RTC 音视频帧。
    @MainActor
    func restart(from mediaTimeUs: Int64) async throws

    /// 解除静态帧冻结，并在需要时恢复播放器。
    @MainActor
    func resumePreviewIfNeeded()

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
    private var previewContentMode = VideoContentMode.fill

    // 运行状态
    private var isConfigured = false
    private var isFrameConversionPending = false
    private var isPlaying = false
    private var isPreviewFrozen = false
    private var lastVideoFrame: VideoFrame?
    private var frozenVideoFrame: VideoFrame?

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

    /// 暂停播放器并返回当前文件时间检查点。
    func pause() -> Int64? {
        guard isConfigured else {
            return nil
        }
        player.pause()
        isPlaying = false
        isPreviewFrozen = true
        frozenVideoFrame = lastVideoFrame
        displayFrozenPreviewIfPossible()
        return Self.microseconds(from: player.currentTime())
    }

    /// 从指定文件时间重新播放，继续向 RTC 输出音视频帧。
    func restart(from mediaTimeUs: Int64) async throws {
        guard isConfigured, let playerItem else {
            throw Self.mediaError("Configure the video player before restarting it")
        }
        let duration = try await playerItem.asset.load(.duration)
        let durationUs = max(Self.microseconds(from: duration) ?? 0, 1)
        let resolvedTimeUs = min(max(mediaTimeUs, 0), durationUs - 1)
        let time = CMTime(value: resolvedTimeUs, timescale: 1_000_000)
        await seek(to: time)
        audioTap?.reset()
        startDisplayLink()
        player.play()
        isPlaying = true
    }

    /// 解除静态帧冻结；播放器尚未运行时同时恢复播放。
    func resumePreviewIfNeeded() {
        guard isConfigured else {
            return
        }
        isPreviewFrozen = false
        frozenVideoFrame = nil
        previewView?.clearPlayerFreezeFrame()
        if !isPlaying {
            startDisplayLink()
            player.play()
            isPlaying = true
        }
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
        previewContentMode = contentMode
        videoView.displayPlayer(player, contentMode: contentMode)
        if isPreviewFrozen {
            displayFrozenPreviewIfPossible()
        } else {
            videoView.clearPlayerFreezeFrame()
        }
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
        previewView?.clearPlayerFreezeFrame()
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        videoOutput = nil
        audioTap = nil
        previewView = nil
        outputWidth = 0
        outputHeight = 0
        outputRotation = .rotation0
        frameRate = 0
        previewContentMode = .fill
        isPreviewFrozen = false
        lastVideoFrame = nil
        frozenVideoFrame = nil
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
                Task { @MainActor [weak self] in
                    self?.recordConvertedFrame(frame)
                }
                try self?.videoFrameListener(frame)
            } catch {
                self?.errorListener(XmaxError.from(error))
            }
            Task { @MainActor [weak self] in
                self?.isFrameConversionPending = false
            }
        }
    }

    func recordConvertedFrame(_ frame: VideoFrame) {
        lastVideoFrame = frame
        guard isPreviewFrozen, !isPlaying else {
            return
        }
        frozenVideoFrame = frame
        displayFrozenPreviewIfPossible()
    }

    func displayFrozenPreviewIfPossible() {
        guard isPreviewFrozen,
              let frozenVideoFrame,
              let previewView else {
            return
        }
        do {
            try previewView.displayPlayerFreezeFrame(
                frozenVideoFrame,
                contentMode: previewContentMode
            )
        } catch {
            errorListener(XmaxError.from(error))
        }
    }

    static func microseconds(from time: CMTime) -> Int64? {
        guard time.isValid, time.isNumeric else {
            return nil
        }
        let seconds = time.seconds
        guard seconds.isFinite,
              seconds >= 0,
              seconds <= Double(Int64.max) / 1_000_000 else {
            return nil
        }
        return Int64((seconds * 1_000_000).rounded())
    }

    static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
