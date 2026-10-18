//
//  InteractionControlling.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 管理生成任务期间的轨迹交互输入。
protocol InteractionControlling: Sendable {
    /// 开始接收当前生成任务的触控轨迹。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 固定的本地媒体规格，作为发送轨迹的像素坐标基准。
    func startInteraction(
        taskID: String,
        videoFormat: RealtimeVideoFormat
    ) async

    /// 停止接收轨迹并清理当前任务。
    func stopInteraction() async

    /// 提交触控轨迹。
    ///
    /// - Parameter frame: 当前视图中采集的轨迹及显示尺寸。
    func submitInteraction(_ frame: InteractionFrame) async
}
