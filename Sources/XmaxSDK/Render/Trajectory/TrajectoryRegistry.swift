//
//  TrajectoryRegistry.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 保存远端视频轨道与轨迹交互能力之间的绑定。
@MainActor
enum TrajectoryRegistry {

    /// 按视频轨道标识保存的交互绑定。
    private static var bindings: [ObjectIdentifier: TrajectoryBinding] = [:]

    /// 登记远端轨道对应的轨迹交互绑定。
    ///
    /// - Parameters:
    ///   - track: 需要登记的远端视频轨道。
    ///   - binding: 轨迹交互绑定。
    static func register(
        _ track: RealtimeVideoTrack,
        binding: TrajectoryBinding
    ) {
        bindings[ObjectIdentifier(track)] = binding
    }

    /// 移除并停用指定轨道的轨迹交互绑定。
    ///
    /// - Parameter track: 需要移除的远端视频轨道。
    static func unregister(
        _ track: RealtimeVideoTrack
    ) {
        bindings.removeValue(forKey: ObjectIdentifier(track))?.invalidate()
    }

    /// 查找指定轨道的轨迹交互绑定。
    ///
    /// - Parameter track: 待查找的远端视频轨道。
    /// - Returns: 已登记的轨迹绑定；未登记时返回 `nil`。
    static func binding(
        for track: RealtimeVideoTrack
    ) -> TrajectoryBinding? {
        bindings[ObjectIdentifier(track)]
    }
}
