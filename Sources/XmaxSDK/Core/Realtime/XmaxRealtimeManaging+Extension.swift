import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 提供常用默认参数，简化实时媒体流创建与生成调用。
public extension XmaxRealtimeManaging {

    /// 使用前置摄像头创建本地相机流并开始预览。
    ///
    /// - Parameter videoFormat: 相机采集的视频规格。
    /// - Returns: 包含本地相机视频轨道的媒体流。
    /// - Throws: 相机权限、RTC 初始化或采集启动失败时抛出错误。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
    }


    /// 根据编码后的图片数据创建本地图片流并开始预览。
    ///
    /// 输出规格使用图片原始尺寸。
    ///
    /// - Parameter imageData: JPEG、PNG 等受支持格式的编码图片数据。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 图片解码、RTC 初始化或媒体流启动失败时抛出错误。
    func createLocalImageStream(
        imageData: Data
    ) async throws -> RealtimeMediaStream {
        try await createLocalImageStream(
            imageData: imageData,
            videoFormat: nil
        )
    }


#if canImport(UIKit)

    /// 根据 UIKit 图片原始尺寸创建本地图片流并开始预览。
    ///
    /// - Parameter image: 用作本地输入的 UIKit 图片。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 图片解码、RTC 初始化或媒体流启动失败时抛出错误。
    func createLocalImageStream(
        image: UIImage
    ) async throws -> RealtimeMediaStream {
        try await createLocalImageStream(
            image: image,
            videoFormat: nil
        )
    }
#endif


    /// 根据图片文件原始尺寸创建本地图片流并开始预览。
    ///
    /// - Parameter fileURL: 本地图片文件 URL。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 文件读取、图片解码、RTC 初始化或媒体流启动失败时抛出错误。
    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createLocalImageStream(
            fileURL: fileURL,
            videoFormat: nil
        )
    }


    /// 根据视频文件原始尺寸创建循环播放的本地音视频流。
    ///
    /// - Parameter fileURL: 本地视频文件 URL。
    /// - Returns: 包含本地视频轨道及可用音频轨道的媒体流。
    /// - Throws: 文件读取、RTC 初始化或媒体流启动失败时抛出错误。
    func createLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createLocalVideoStream(
            fileURL: fileURL,
            videoFormat: nil
        )
    }


    /// 使用已缓存的生成条件开始或更新生成。
    ///
    /// 首次开始生成时没有缓存条件，因此仍需调用带 `context` 参数的重载。
    ///
    /// - Throws: 没有可复用条件，或生成启动及更新失败时抛出错误。
    func startGeneration() async throws {
        try await startGeneration(context: nil)
    }


    /// 使用当前本地流和已缓存条件按需连接并开始生成。
    ///
    /// 首次开始生成时没有缓存条件，因此仍需调用带 `context` 参数的重载。
    ///
    /// - Parameter localStream: 当前 Manager 创建并持有的本地媒体流。
    /// - Returns: 当前 RTC 连接对应的远端媒体流。
    /// - Throws: 没有可复用条件、本地流无效，或连接及生成启动失败时抛出错误。
    func startGeneration(
        localStream: RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        try await startGeneration(
            localStream: localStream,
            context: nil
        )
    }
}
