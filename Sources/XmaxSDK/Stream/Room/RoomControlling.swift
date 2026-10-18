//
//  RoomControlling.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 定义 RTC 房间生命周期和业务信令发送能力。
protocol RoomControlling: Actor {

    /// 加入实时房间，并在异步边界确认连接操作仍有效。
    ///
    /// - Parameters:
    ///   - connection: 服务端分配的 RTC 连接信息。
    ///   - ensureActive: 检查当前连接操作有效性的回调。
    /// - Throws: 房间状态无效、RTC 进房失败、超时或操作取消时抛出错误。
    func join(
        connection: RealtimeSessionConnection,
        ensureActive: @escaping @Sendable () throws -> Void
    ) async throws

    /// 停止房间心跳并离开当前 RTC 房间。
    func leave() async

    /// 将生成开始信令提交到房间发送队列。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 当前生成条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否保留源比例并填充生成画布。
    /// - Throws: 房间未就绪、信令编码或入队失败时抛出错误。
    func startGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize?,
        context: RealtimeContext,
        faceRestoration: Bool,
        paddingContain: Bool
    ) throws

    /// 将生成条件变更信令提交到房间发送队列。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 服务端生成使用的视频规格。
    ///   - targetSize: 生成后回传的像素尺寸；`nil` 表示保持生成尺寸。
    ///   - context: 当前生成条件。
    ///   - faceRestoration: 是否回贴原始人脸。
    ///   - paddingContain: 是否保留源比例并填充生成画布。
    /// - Throws: 房间未就绪、调用取消、信令编码或入队失败时抛出错误。
    func changeGenerationCondition(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        targetSize: CGSize?,
        context: RealtimeContext,
        faceRestoration: Bool,
        paddingContain: Bool
    ) throws

    /// 调整当前生成任务的回传尺寸。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - targetSize: 生成后回传的整数像素尺寸。
    ///   - ensureActive: 发送前确认当前配置操作仍有效。
    /// - Throws: 操作已取消、房间未就绪或信令发送失败时抛出错误。
    func changeTargetSize(
        taskID: String,
        targetSize: CGSize,
        ensureActive: @Sendable () throws -> Void
    ) async throws

    /// 提交生成停止信令，未进房或任务为空时忽略。
    ///
    /// - Parameter taskID: 需要停止的生成任务标识。
    /// - Throws: 停止信令编码或入队失败时抛出错误。
    func stopGeneration(taskID: String) throws

    /// 提交当前生成任务的交互轨迹。
    ///
    /// - Parameters:
    ///   - taskID: 接收轨迹的任务标识；空值时不发送。
    ///   - points: 媒体归一化坐标点，取值范围为 `[0, 1]`；空数组时不发送。
    /// - Throws: 房间未就绪、轨迹编码或信令入队失败时抛出错误。
    func sendTracks(
        taskID: String,
        points: [RealtimePoint]
    ) throws
}
