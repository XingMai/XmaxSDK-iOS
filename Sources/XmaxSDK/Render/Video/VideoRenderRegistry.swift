//
//  VideoRenderRegistry.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 保存实时视频轨道与底层渲染能力之间的内部绑定关系。
@MainActor
enum VideoRenderRegistry {

    /// 渲染绑定
    private static var bindings: [ObjectIdentifier: VideoRenderBinding] = [:]

    /// 登记视频轨道对应的渲染绑定。
    ///
    /// - Parameters:
    ///   - track: 需要登记的视频轨道。
    ///   - binding: 轨道使用的视图绑定能力。
    static func register(
        _ track: RealtimeVideoTrack,
        binding: VideoRenderBinding
    ) {
        bindings[ObjectIdentifier(track)] = binding
    }

    /// 移除指定轨道的渲染绑定记录。
    ///
    /// - Parameter track: 需要移除的视频轨道。
    static func unregister(_ track: RealtimeVideoTrack) {
        bindings.removeValue(forKey: ObjectIdentifier(track))
    }

    /// 查找视频轨道对应的渲染绑定。
    ///
    /// - Parameter track: 待查找的视频轨道。
    /// - Returns: 已登记的绑定；未登记时返回 `nil`。
    static func binding(
        for track: RealtimeVideoTrack
    ) -> VideoRenderBinding? {
        bindings[ObjectIdentifier(track)]
    }
}
