//
//  MediaSourceController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import Foundation
import UIKit

/// 协调本地视频文件元数据、输出格式和解耦的音视频播放器。
final class MediaSourceController: MediaSourceControlling, @unchecked Sendable {

    /// 读取文件媒体元数据的组件。
    private let metadataManager: any MediaFileMetadataManaging

    /// 提供媒体尺寸规则和模型默认帧率的服务。
    private let mediaService: any MediaServicing

    /// 负责解码、帧输出和本地预览的播放器。
    private let playerController: any VideoPlayerControlling

    /// 保护文件媒体配置和运行状态。
    private let stateLock = NSLock()

    /// 已准备完成的媒体帧输出配置。
    private var configuration: MediaSourceConfiguration?

    /// 文件媒体是否正在播放并输出帧。
    private var isRunning = false

    /// 连接文件元数据、模型规则和音视频播放组件。
    init(
        metadataManager: any MediaFileMetadataManaging,
        mediaService: any MediaServicing,
        playerController: any VideoPlayerControlling
    ) {
        self.metadataManager = metadataManager
        self.mediaService = mediaService
        self.playerController = playerController
    }

    /// 当前文件媒体是否包含音轨。
    var hasAudio: Bool {
        stateLock.withLock { configuration?.hasAudio ?? false }
    }

    /// 当前本地音频预览音量，范围为 0...1。
    var localAudioVolume: Float {
        get async {
            await playerController.localAudioVolume
        }
    }

    /// 准备本地视频文件和输出格式。
    ///
    /// - Parameter fileURL: 可读取的本地视频文件地址。
    /// - Returns: 保留源视频显示比例的媒体输出配置。
    /// - Throws: 文件无法读取、视频轨道缺失或输出规格无效时抛出错误。
    func prepare(
        fileURL: URL
    ) async throws -> MediaSourceConfiguration {
        guard stateLock.withLock({ configuration == nil }) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current media source before preparing " +
                    "another file"
            )
        }

        do {
            let metadata = try await metadataManager.readMetadata(
                fileURL: fileURL
            )
            let resolvedFormat = try resolveVideoFormat(
                metadata: metadata
            )
            try await playerController.configure(
                fileURL: fileURL,
                outputWidth: resolvedFormat.width,
                outputHeight: resolvedFormat.height,
                rotation: metadata.rotation,
                frameRate: resolvedFormat.fps,
                hasAudio: metadata.hasAudio,
                durationSeconds: metadata.durationSeconds
            )

            let configuration = MediaSourceConfiguration(
                videoFormat: resolvedFormat,
                hasAudio: metadata.hasAudio
            )
            stateLock.withLock {
                self.configuration = configuration
            }
            return configuration
        } catch {
            throw XmaxError.from(error)
        }
    }

    /// 从文件起点开始循环输出音视频帧。
    ///
    /// - Throws: 媒体未准备、已在运行或播放器启动失败时抛出错误。
    func start() async throws {
        try beginRunning()
        do {
            try await playerController.start()
        } catch {
            await rollbackRunning()
            throw XmaxError.from(error)
        }
    }

    /// 静音或恢复本地音频预览，不影响播放器和 RTC 音频帧输出。
    ///
    /// - Parameter muted: `true` 表示仅静音本地播放器；
    func setLocalAudioPreviewMuted(
        _ muted: Bool
    ) async {
        guard hasAudio else {
            return
        }
        await playerController.setLocalAudioPreviewMuted(muted)
    }

    /// 设置本地音频预览音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 `0...1` 的音量。
    func setLocalAudioVolume(
        _ volume: Float
    ) async {
        await playerController.setLocalAudioVolume(volume)
    }

    /// 将解码预览绑定到指定视图。
    ///
    /// - Parameters:
    ///   - view: 接收预览画面的视图。
    ///   - contentMode: 画面的缩放与裁剪方式。
    /// - Throws: 预览绑定失败时抛出错误。
    @MainActor
    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        try playerController.attachPreview(
            to: view,
            contentMode: contentMode
        )
    }

    /// 从指定视图解除解码预览。
    ///
    /// - Parameter view: 需要解除预览的视图。
    @MainActor
    func detachPreview(
        from view: UIView
    ) {
        playerController.detachPreview(from: view)
    }

    /// 停止输出并释放解码与本地音频播放资源。
    func stop() async {
        stateLock.withLock {
            isRunning = false
            configuration = nil
        }
        await playerController.stop()
    }
}

private extension MediaSourceController {

    /// 校验媒体已经准备并标记开始运行。
    ///
    /// - Throws: 媒体尚未准备或已在运行时抛出错误。
    func beginRunning() throws {
        try stateLock.withLock {
            guard configuration != nil else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Prepare the media file before starting it"
                )
            }
            guard !isRunning else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Local media source is already active"
                )
            }
            isRunning = true
        }
    }

    /// 清除运行标记并停止播放器。
    func rollbackRunning() async {
        stateLock.withLock {
            isRunning = false
        }
        await playerController.stop()
    }

    /// 根据源视频显示方向和模型面积上限计算输出规格。
    ///
    /// - Parameter metadata: 源视频的编码尺寸、旋转及音频信息。
    /// - Returns: 保留源显示比例并使用模型默认帧率的输出规格。
    /// - Throws: 解析出的输出规格无效时抛出错误。
    func resolveVideoFormat(
        metadata: MediaFileMetadata
    ) throws -> RealtimeVideoFormat {
        let swapsDimensions = metadata.rotation == .rotation90 ||
            metadata.rotation == .rotation270
        let displayWidth = swapsDimensions ? metadata.height : metadata.width
        let displayHeight = swapsDimensions ? metadata.width : metadata.height
        let resolvedMediaSize = try mediaService.resolveMediaSize(
            CGSize(width: displayWidth, height: displayHeight),
            source: .video
        )
        let resolvedFormat = RealtimeVideoFormat(
            width: Int(resolvedMediaSize.width),
            height: Int(resolvedMediaSize.height),
            fps: mediaService.model.defaultFrameRate
        )
        try resolvedFormat.validate()
        return resolvedFormat
    }
}
