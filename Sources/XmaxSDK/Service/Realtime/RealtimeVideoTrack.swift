//
//  RealtimeVideoTrack.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 实时视频轨道及其动态元数据。
public final class RealtimeVideoTrack: @unchecked Sendable {

    /// 视频轨道标识。
    public let id: String

    /// 保护可随方向变化更新的轨道元数据。
    private let metadataLock = NSLock()

    /// 受锁保护的媒体尺寸和摄像头位置。
    private var metadata: Metadata

    /// 视图通知的当前摄像头显示方向。
    @MainActor var displayOrientation: CameraOrientation?

    /// 视图方向变化时通知媒体链路；参数表示是否发生横竖屏切换。
    @MainActor var orientationChangeHandler: ((_ changedAxis: Bool) -> Void)?

    /// 创建具有指定标识和初始元数据的视频轨道。
    ///
    /// - Parameters:
    ///   - id: 轨道的唯一标识。
    ///   - videoFormat: 初始视频规格；尚未确定时传入 `nil`。
    ///   - position: 本地摄像头位置；非摄像头轨道传入 `nil`。
    init(
        id: String,
        videoFormat: RealtimeVideoFormat? = nil,
        position: CameraPosition? = nil
    ) {
        self.id = id
        metadata = Metadata(
            videoFormat: videoFormat,
            position: position
        )
    }

    /// 当前视频轨道使用的视频格式。
    public var videoFormat: RealtimeVideoFormat? {
        metadataLock.withLock { metadata.videoFormat }
    }

    /// 本地相机轨道当前使用的摄像头位置。
    public var position: CameraPosition? {
        metadataLock.withLock { metadata.position }
    }

    /// 更新视频轨道的当前规格。
    ///
    /// - Parameter videoFormat: 新的尺寸、帧率和编码配置。
    func updateVideoFormat(
        _ videoFormat: RealtimeVideoFormat
    ) {
        metadataLock.withLock {
            metadata.videoFormat = videoFormat
        }
    }

    /// 更新本地相机轨道的摄像头位置。
    ///
    /// - Parameter position: 当前采集使用的摄像头位置。
    func updatePosition(
        _ position: CameraPosition
    ) {
        metadataLock.withLock {
            metadata.position = position
        }
    }
}

private extension RealtimeVideoTrack {

    /// 保存可在采集与渲染期间更新的视频规格和摄像头位置。
    struct Metadata {

        /// 当前处理后媒体的尺寸、帧率和编码配置。
        var videoFormat: RealtimeVideoFormat?

        /// 轨道来自摄像头时对应的镜头位置。
        var position: CameraPosition?
    }
}
