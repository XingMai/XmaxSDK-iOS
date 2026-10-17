//
//  XmaxRealtimeManaging+Extension.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 提供常用默认参数，简化实时媒体流创建与生成调用。
public extension XmaxRealtimeManaging {

    /// 使用当前模型的默认视频规格创建本地相机流。
    ///
    /// - Parameters:
    ///   - position: 采集使用的摄像头位置，默认为前置摄像头。
    ///   - useMicrophone: 是否使用麦克风，默认关闭；连接时开始采集，断开时停止。
    /// - Returns: 包含本地相机视频轨道的媒体流。
    /// - Throws: 配置无效、所需权限被拒绝、操作冲突或采集启动失败时抛出错误。
    func createLocalCameraStream(
        position: CameraPosition = .front,
        useMicrophone: Bool = false
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: options.model.defaultCameraVideoFormat,
            position: position,
            useMicrophone: useMicrophone
        )
    }

    /// 使用前置摄像头创建本地相机流并开始预览。
    ///
    /// - Parameters:
    ///   - videoFormat: 相机采集的视频规格。
    ///   - useMicrophone: 是否使用麦克风，默认关闭；连接时开始采集，断开时停止。
    /// - Returns: 包含本地相机视频轨道的媒体流。
    /// - Throws: 配置无效、所需权限被拒绝、操作冲突或采集启动失败时抛出错误。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        useMicrophone: Bool = false
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front,
            useMicrophone: useMicrophone
        )
    }

    /// 创建不使用麦克风的本地相机流。
    ///
    /// - Parameters:
    ///   - videoFormat: 相机采集的视频规格。
    ///   - position: 首次启用的摄像头位置。
    /// - Returns: 包含本地相机视频轨道的媒体流。
    /// - Throws: 配置无效、所需权限被拒绝、操作冲突或采集启动失败时抛出错误。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: videoFormat,
            position: position,
            useMicrophone: false
        )
    }

    /// 使用已缓存的生成条件开始或更新生成。
    ///
    /// 首次开始生成时没有缓存条件，因此仍需调用带 `context` 参数的重载。
    ///
    /// - Parameter faceRestoration: 是否回贴原始人脸，默认关闭。
    /// - Throws: 没有可复用条件，或生成启动及更新失败时抛出错误。
    func startGeneration(faceRestoration: Bool = false) async throws {
        try await startGeneration(context: nil, faceRestoration: faceRestoration)
    }

    /// 开始或更新生成，默认关闭人脸还原。
    ///
    /// - Parameter context: 本次生成条件；传入 `nil` 时复用缓存条件。
    /// - Throws: 条件无效或生成启动、更新失败时抛出错误。
    func startGeneration(context: RealtimeContext?) async throws {
        try await startGeneration(context: context, faceRestoration: false)
    }

    /// 使用当前本地流按需连接并开始生成，默认关闭人脸还原。
    ///
    /// - Parameters:
    ///   - localStream: 当前 Manager 创建并持有的本地媒体流。
    ///   - context: 本次生成条件；首次生成不能为空。
    /// - Returns: 当前连接对应的远端媒体流。
    /// - Throws: 本地流无效、连接失败或生成启动失败时抛出错误。
    func startGeneration(
        localStream: RealtimeMediaStream,
        context: RealtimeContext?
    ) async throws -> RealtimeMediaStream {
        try await startGeneration(
            localStream: localStream,
            context: context,
            faceRestoration: false
        )
    }

    /// 使用当前本地流和已缓存条件按需连接并开始生成。
    ///
    /// 首次开始生成时没有缓存条件，因此仍需调用带 `context` 参数的重载。
    ///
    /// - Parameters:
    ///   - localStream: 当前 Manager 创建并持有的本地媒体流。
    ///   - faceRestoration: 是否回贴原始人脸，默认关闭。
    /// - Returns: 当前 RTC 连接对应的远端媒体流。
    /// - Throws: 没有可复用条件、本地流无效，或连接及生成启动失败时抛出错误。
    func startGeneration(
        localStream: RealtimeMediaStream,
        faceRestoration: Bool = false
    ) async throws -> RealtimeMediaStream {
        try await startGeneration(
            localStream: localStream,
            context: nil,
            faceRestoration: faceRestoration
        )
    }
}
