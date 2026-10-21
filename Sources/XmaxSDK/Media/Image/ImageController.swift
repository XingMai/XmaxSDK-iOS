//
//  ImageController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import Foundation

/// 协调本地图片解码、循环帧输出和预览资源。
final class ImageController: ImageControlling, @unchecked Sendable {

    /// 图片本地视频轨道标识。
    private static let localVideoTrackID = "video0"

    /// 配置 RTC 外部视频源的组件。
    private let rtcManager: any RtcManaging

    /// 解码图片并生成指定尺寸的图像。
    private let imageManager: any ImageManaging

    /// 提供模型默认帧率的服务。
    private let mediaService: any MediaServicing

    /// 接收图片视频帧的回调。
    private let frameListener: MediaVideoFrameListener

    /// 保护图片轨道和持续输出任务。
    private let stateLock = NSLock()

    /// 当前图片对应的视频轨道。
    private var activeTrack: RealtimeVideoTrack?

    /// 按目标帧率持续输出图片帧的任务。
    private var outputTask: Task<Void, Never>?

    /// 创建图片解码、预览和持续帧输出控制器。
    init(
        rtcManager: any RtcManaging,
        imageManager: any ImageManaging = ImageManager(),
        mediaService: any MediaServicing = MediaService(),
        frameListener: @escaping MediaVideoFrameListener
    ) {
        self.rtcManager = rtcManager
        self.imageManager = imageManager
        self.mediaService = mediaService
        self.frameListener = frameListener
    }

    /// 当前可供预览和发送的图片轨道。
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
    }

    /// 从已解码的图片创建媒体流并开始持续输出视频帧。
    ///
    /// - Parameter decodedImage: 已完成方向处理和像素解码的图片。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 已有活动图片流、格式无效、图片处理或帧输出启动失败时抛出错误。
    func createLocalImageStream(
        decodedImage: any DecodedImage
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .decoded(decodedImage))
    }

    /// 从编码后的图片数据创建媒体流并开始持续输出视频帧。
    ///
    /// - Parameter imageData: 非空的图片文件编码数据。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 已有活动图片流、数据或格式无效、图片解码或帧输出启动失败时抛出错误。
    func createLocalImageStream(
        imageData: Data
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .data(imageData))
    }

    /// 从本地图片文件创建媒体流并开始持续输出视频帧。
    ///
    /// - Parameter fileURL: 可读取的本地图片文件地址。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 已有活动图片流、文件读取、格式校验、图片解码或帧输出启动失败时抛出错误。
    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .file(fileURL))
    }

    /// 停止并等待图片帧输出任务结束，释放当前轨道及预览绑定；无活动流时不执行操作。
    func stopLocalImageStream() async {
        let (track, task) = stateLock.withLock {
            let resources = (activeTrack, outputTask)
            activeTrack = nil
            outputTask = nil
            return resources
        }

        task?.cancel()
        await task?.value

        if let track {
            await MainActor.run {
                do {
                    try VideoRenderRegistry.binding(for: track)?.detach()
                } catch {
                    XmaxLogger.realtime.error(
                        message: "解除本地图片预览绑定失败 (Failed to Detach Local Image Preview)\n" +
                            "└─ \(XmaxLogger.localized("原因：", "Reason: "))" + (error as NSError).localizedDescription
                    )
                }

                VideoRenderRegistry.unregister(track)
            }
        }
    }
}

private extension ImageController {

    /// 统一表示编码数据、已解码图片和本地图片文件。
    enum ImageInput: Sendable {

        /// 待解码的图片数据。
        case data(Data)

        /// 已解码的图片，可直接参与图像处理。
        case decoded(any DecodedImage)

        /// 本地图片文件。
        case file(URL)
    }

    /// 解码图片并建立静态预览及周期视频帧输出。
    ///
    /// - Parameter input: 图片来源。
    /// - Returns: 持有图片视频轨道的本地媒体流。
    /// - Throws: 已有图片流、图片读取解码、帧处理或外部视频源配置失败时抛出错误。
    func createStream(
        input: ImageInput
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local image stream before creating another one"
            )
        }

        var track: RealtimeVideoTrack?

        do {
            let image = try decode(input)
            let resolvedFormat = try resolveVideoFormat(
                sourceMediaSize: image.size
            )
            let frame = try image.makeVideoFrame(
                width: resolvedFormat.width,
                height: resolvedFormat.height
            )
            let localTrack = RealtimeVideoTrack(
                id: Self.localVideoTrackID,
                videoFormat: resolvedFormat
            )
            track = localTrack

            try rtcManager.useExternalVideoSource()
            await MainActor.run {
                VideoRenderRegistry.register(
                    localTrack,
                    binding: VideoRenderBinding(imageFrame: frame)
                )
            }

            try emitFrame(frame)
            let task = startFrameOutput(frame: frame, frameRate: resolvedFormat.fps)
            stateLock.withLock {
                activeTrack = localTrack
                outputTask = task
            }

            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: localTrack
            )
        } catch {
            if let track {
                await MainActor.run {
                    VideoRenderRegistry.unregister(track)
                }
            }

            throw XmaxError.from(error)
        }
    }

    /// 将统一图片来源转换为已解码图片。
    ///
    /// - Parameter input: 编码数据、图片对象或文件来源。
    /// - Returns: 可用于视频帧转换的图片。
    /// - Throws: 文件地址或数据无效、文件读取或图片解码失败时抛出错误。
    func decode(
        _ input: ImageInput
    ) throws -> any DecodedImage {
        let data: Data

        switch input {
        case .decoded(let image):
            return image
        case .data(let imageData):
            data = imageData
        case .file(let fileURL):
            guard fileURL.isFileURL, !fileURL.path.isEmpty else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Local image file URL must reference a file"
                )
            }

            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        }

        guard !data.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image source data must not be empty"
            )
        }

        return try imageManager.decode(data)
    }

    /// 根据模型面积上限计算保持图片比例的视频输出规格。
    ///
    /// - Parameter sourceMediaSize: 图片的原始像素尺寸。
    /// - Returns: 采用模型默认帧率的图片视频规格。
    /// - Throws: 图片尺寸或输出格式无效时抛出错误。
    func resolveVideoFormat(
        sourceMediaSize: CGSize
    ) throws -> RealtimeVideoFormat {
        let resolvedMediaSize = try mediaService.resolveMediaSize(sourceMediaSize, source: .image)
        let resolvedFormat = RealtimeVideoFormat(
            width: Int(resolvedMediaSize.width),
            height: Int(resolvedMediaSize.height),
            fps: mediaService.model.defaultFrameRate
        )
        try resolvedFormat.validate()
        return resolvedFormat
    }

    /// 按指定帧率重复输出相同图片的像素数据。
    ///
    /// - Parameters:
    ///   - frame: 可复用像素数据的图片帧。
    ///   - frameRate: 每秒输出帧数。
    /// - Returns: 可取消的周期输出任务。
    func startFrameOutput(
        frame: VideoFrame,
        frameRate: Int
    ) -> Task<Void, Never> {
        let interval = max(UInt64(1000000000 / frameRate), 1)

        return Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled, let self else {
                    return
                }

                do {
                    try self.emitFrame(frame)
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    XmaxLogger.media.error(message: "图片帧推送失败 (Image Frame Push Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.localizedDescription)")
                }
            }
        }
    }

    /// 使用当前主机时间戳向监听器提交图片帧。
    ///
    /// - Parameter frame: 提供像素数据和格式的图片帧。
    /// - Throws: 帧更新或监听器处理失败时抛出错误。
    func emitFrame(
        _ frame: VideoFrame
    ) throws {
        let timestampUs = Int64(
            min(
                DispatchTime.now().uptimeNanoseconds / 1000,
                UInt64(Int64.max)
            )
        )
        try frameListener(try frame.updating(timestampUs: timestampUs))
    }
}
