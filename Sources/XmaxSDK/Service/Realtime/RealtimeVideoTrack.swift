//
//  RealtimeVideoTrack.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 实时视频轨道及其动态元数据。
public final class RealtimeVideoTrack: @unchecked Sendable {

    // 轨道信息
    /// 视频轨道标识。
    public let id: String

    // 动态元数据
    private let metadataLock = NSLock()
    private var metadata: Metadata

    // 显示方向事件
    @MainActor var displayOrientation: CameraOrientation?
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

    // 当前媒体规格
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
    func updateVideoFormat(_ videoFormat: RealtimeVideoFormat) {
        metadataLock.withLock {
            metadata.videoFormat = videoFormat
        }
    }

    /// 更新本地相机轨道的摄像头位置。
    ///
    /// - Parameter position: 当前采集使用的摄像头位置。
    func updatePosition(_ position: CameraPosition) {
        metadataLock.withLock {
            metadata.position = position
        }
    }
}

private extension RealtimeVideoTrack {
    /// 保存可在采集与渲染期间更新的视频规格和摄像头位置。
    struct Metadata {

        // 当前媒体规格
        var videoFormat: RealtimeVideoFormat?
        var position: CameraPosition?
    }
}
