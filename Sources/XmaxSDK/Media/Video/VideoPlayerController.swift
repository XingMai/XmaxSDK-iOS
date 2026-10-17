//
//  VideoPlayerController.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit

/// 定义基于统一媒体时间轴的文件音视频输出能力。
protocol VideoPlayerControlling: Sendable {

    // 音频预览
    /// 当前本地音频预览音量。
    @MainActor
    var localAudioVolume: Float { get }

    /// 配置本地视频文件及最终 RTC 输出格式。
    ///
    /// - Parameters:
    ///   - fileURL: 已读取元数据的本地视频文件地址。
    ///   - outputWidth: 输出视频帧的像素宽度。
    ///   - outputHeight: 输出视频帧的像素高度。
    ///   - rotation: 文件元数据中的视频旋转方向。
    ///   - frameRate: 输出视频帧率。
    ///   - hasAudio: 文件元数据中的音频轨道标记。
    ///   - durationSeconds: 文件元数据中的原始时长，单位为秒。
    /// - Throws: 文件、输出格式或播放器状态无效时抛出错误。
    @MainActor
    func configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool,
        durationSeconds: Double
    ) throws

    /// 启动共用播放时间轴的本地预览与音视频帧输出。
    ///
    /// - Throws: 播放器未配置或已经启动时抛出错误。
    @MainActor
    func start() async throws

    /// 静音或恢复本地音频预览，不改变音视频帧输出。
    ///
    /// - Parameter muted: 是否将本地音频播放音量置零。
    @MainActor
    func setLocalAudioPreviewMuted(_ muted: Bool)

    /// 设置本地音频预览音量。
    ///
    /// - Parameter volume: 已校验的预览音量，范围为 `0...1`。
    @MainActor
    func setLocalAudioVolume(_ volume: Float)

    /// 将解码视频预览绑定到 SDK 视频视图。
    ///
    /// - Parameters:
    ///   - view: 接收预览的 `XmaxVideoView`。
    ///   - contentMode: 视频画面的缩放与裁剪方式。
    /// - Throws: 视图不是 `XmaxVideoView` 时抛出错误。
    @MainActor
    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws

    /// 从指定 SDK 视频视图解除解码预览。
    ///
    /// - Parameter view: 需要解除预览的视图。
    @MainActor
    func detachPreview(from view: UIView)

    /// 停止解码并等待全部 reader 在所属任务内安全退出。
    @MainActor
    func stop() async
}

/// 使用 AVAssetReader 解码共享时间轴上的本地音视频帧。
@MainActor
final class VideoPlayerController: VideoPlayerControlling {

    /// 保存文件解码、旋转、采样和循环播放所需配置。
    private struct PlaybackConfiguration: Sendable {

        // 文件来源
        let fileURL: URL


        // 视频输出规格
        let outputWidth: Int
        let outputHeight: Int
        let rotation: VideoRotation
        let frameRate: Int


        // 媒体播放信息
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

    /// 创建共享时间轴的视频解码和本地音频播放组件。
    ///
    /// - Parameters:
    ///   - videoFrameListener: 接收视频帧的回调。
    ///   - audioFrameListener: 接收 10 ms PCM 音频帧的回调。
    ///   - errorListener: 接收非取消播放错误的回调。
    init(
        videoFrameListener: @escaping MediaVideoFrameListener,
        audioFrameListener: @escaping MediaAudioFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.videoFrameListener = videoFrameListener
        self.audioFrameListener = audioFrameListener
        self.errorListener = errorListener
    }


    // 音频预览
    var localAudioVolume: Float {
        audioPreviewPlayer.currentVolume
    }

    /// 配置本地视频文件及最终 RTC 输出格式。
    ///
    /// - Parameters:
    ///   - fileURL: 已读取元数据的本地视频文件地址。
    ///   - outputWidth: 输出视频帧的像素宽度。
    ///   - outputHeight: 输出视频帧的像素高度。
    ///   - rotation: 文件元数据中的视频旋转方向。
    ///   - frameRate: 输出视频帧率。
    ///   - hasAudio: 文件元数据中的音频轨道标记。
    ///   - durationSeconds: 文件元数据中的原始时长，单位为秒。
    /// - Throws: 文件、输出格式或播放器状态无效时抛出错误。
    func configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool,
        durationSeconds: Double
    ) throws {
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

    /// 启动共用播放时间轴的本地预览与音视频帧输出。
    ///
    /// - Throws: 播放器未配置或已经启动时抛出错误。
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
                        do {
                            try videoListener(frame)
                        } catch {
                            XmaxLogger.media.error(message: "视频帧推送失败 (Video Frame Push Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.localizedDescription)")
                        }
                    },
                    audioHandler: { frame in
                        audioPreviewPlayer.enqueue(frame)
                        do {
                            try audioListener(frame)
                        } catch {
                            XmaxLogger.media.error(message: "音频帧推送失败 (Audio Frame Push Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.localizedDescription)")
                        }
                    }
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorListener(XmaxError.from(error))
            }
        }
    }

    /// 静音或恢复本地音频预览，不改变音视频帧输出。
    ///
    /// - Parameter muted: 是否将本地音频播放音量置零。
    func setLocalAudioPreviewMuted(_ muted: Bool) {
        audioPreviewPlayer.setMuted(muted)
    }

    /// 设置本地音频预览音量。
    ///
    /// - Parameter volume: 已校验的预览音量，范围为 `0...1`。
    func setLocalAudioVolume(_ volume: Float) {
        audioPreviewPlayer.setVolume(volume)
    }

    /// 将解码视频预览绑定到 SDK 视频视图。
    ///
    /// - Parameters:
    ///   - view: 接收预览的 `XmaxVideoView`。
    ///   - contentMode: 视频画面的缩放与裁剪方式。
    /// - Throws: 视图不是 `XmaxVideoView` 时抛出错误。
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

    /// 从指定 SDK 视频视图解除解码预览。
    ///
    /// - Parameter view: 需要解除预览的视图。
    func detachPreview(from view: UIView) {
        guard let videoView = view as? XmaxVideoView else { return }
        previewPresenter.detach(from: videoView)
    }

    /// 停止解码并等待全部 reader 在所属任务内安全退出。
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
    /// 同步接收共享时间轴输出的视频帧。
    typealias VideoHandler = @Sendable (VideoFrame) throws -> Void
    /// 同步接收共享时间轴输出的固定长度 PCM 帧。
    typealias AudioHandler = @Sendable (AudioFrame) throws -> Void

    /// 并行运行使用同一主机时钟的音视频解码循环。
    ///
    /// - Parameters:
    ///   - configuration: 文件与输出规格配置。
    ///   - timeline: 音视频共用的循环播放时间轴。
    ///   - videoHandler: 按时间轴输出的视频帧回调。
    ///   - audioHandler: 按时间轴输出的音频帧回调。
    /// - Throws: 媒体读取、解码、回调处理失败或任务取消时抛出错误。
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

    /// 循环解码视频并按共享时间轴输出目标规格的视频帧。
    ///
    /// - Parameters:
    ///   - configuration: 视频文件、输出尺寸和采样帧率。
    ///   - timeline: 用于计算循环播放时刻的共享时间轴。
    ///   - handler: 接收定时视频帧的回调。
    /// - Throws: 视频轨道不可用、解码失败、整轮无有效帧、回调失败或任务取消时抛出错误。
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
                let frame: VideoFrame
                do {
                    frame = try NV12VideoFrameConverter.convert(
                        pixelBuffer: pixelBuffer,
                        outputWidth: configuration.outputWidth,
                        outputHeight: configuration.outputHeight,
                        rotation: configuration.rotation,
                        timestampUs: Int64(target / 1_000)
                    )
                } catch {
                    XmaxLogger.media.error(message: "视频帧转换失败 (Video Frame Conversion Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.localizedDescription)")
                    continue
                }
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

    /// 循环解码 PCM 并补齐每轮音频时间轴。
    ///
    /// - Parameters:
    ///   - configuration: 视频文件及音频配置。
    ///   - timeline: 用于计算循环播放时刻的共享时间轴。
    ///   - handler: 接收固定长度音频帧的回调。
    /// - Throws: 音频轨道不可用、解码或回调失败，以及任务取消时抛出错误。
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

    /// 按共享时钟输出音频包，并丢弃超过延迟阈值的包。
    ///
    /// - Parameters:
    ///   - packetizer: 提供待输出 PCM 包的分帧器。
    ///   - loopIndex: 从零开始的循环播放轮次。
    ///   - timeline: 音视频共用的播放时间轴。
    ///   - handler: 接收带主机时间戳音频帧的回调。
    /// - Throws: 等待被取消或音频回调失败时抛出错误。
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
                    timestampUs: Int64(target / 1_000)
                )
            )
        }
    }

    /// 复制音频样本缓冲区中的 PCM 数据。
    ///
    /// - Parameter sampleBuffer: 包含解码 PCM 的样本缓冲区。
    /// - Returns: 复制后的 PCM 数据；无数据缓冲区时返回空数据。
    /// - Throws: 读取底层 PCM 数据失败时抛出错误。
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

    /// 等待指定的主机单调时钟时刻。
    ///
    /// - Parameter target: 目标时刻，单位为纳秒。
    /// - Throws: 等待被取消时抛出取消错误。
    nonisolated static func sleep(untilNanoseconds target: UInt64) async throws {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < target else { return }
        try await Task.sleep(nanoseconds: target - now)
    }

    /// 构造文件音视频播放错误。
    ///
    /// - Parameter message: 错误描述。
    /// - Returns: 包含指定描述的媒体错误。
    nonisolated static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
