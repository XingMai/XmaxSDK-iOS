//
//  MediaSourceControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import UIKit

/// 定义本地视频文件准备、循环帧输出及预览管理能力。
protocol MediaSourceControlling: Sendable {

    /// 当前本地音频预览音量。
    var localAudioVolume: Float { get async }

    /// 当前媒体是否包含音频轨道。
    var hasAudio: Bool { get }

    /// 准备本地视频文件和输出格式。
    ///
    /// - Parameter fileURL: 可读取的本地视频文件地址。
    /// - Returns: 保留源视频显示比例的媒体输出配置。
    /// - Throws: 文件无法读取、视频轨道缺失或输出规格无效时抛出错误。
    func prepare(
        fileURL: URL
    ) async throws -> MediaSourceConfiguration

    /// 从文件起点开始循环输出音视频帧。
    ///
    /// - Throws: 媒体未准备、已在运行或播放器启动失败时抛出错误。
    func start() async throws

    /// 静音或恢复本地音频预览，不影响播放器和 RTC 音频帧输出。
    ///
    /// - Parameter muted: `true` 表示仅静音本地播放器；
    ///   `false` 表示恢复本地播放器音量。
    func setLocalAudioPreviewMuted(
        _ muted: Bool
    ) async

    /// 设置本地音频预览音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 `0...1` 的音量。
    func setLocalAudioVolume(
        _ volume: Float
    ) async

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
    ) throws

    /// 从指定视图解除解码预览。
    ///
    /// - Parameter view: 需要解除预览的视图。
    @MainActor
    func detachPreview(
        from view: UIView
    )

    /// 停止输出并释放解码与本地音频播放资源。
    func stop() async
}
