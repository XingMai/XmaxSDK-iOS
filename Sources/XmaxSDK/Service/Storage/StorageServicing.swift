//
//  StorageServicing.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 定义图片和视频的上传、下载及图片安全检查能力。
protocol StorageServicing: Sendable {

    /// 上传图片数据。
    ///
    /// - Parameters:
    ///   - data: 编码后的图片文件数据。
    ///   - fileName: 包含扩展名的文件名，用于构造对象路径。
    ///   - contentType: 文件的 MIME 类型。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadImage(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传本地图片文件。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件 URL。
    ///   - contentType: 文件 MIME 类型；`nil` 时根据文件名推断。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 文件无效、凭证获取或上传失败时抛出错误。
    func uploadImageFile(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传图片数据并通过内容安全检查。
    ///
    /// - Parameters:
    ///   - data: 编码后的图片文件数据。
    ///   - fileName: 包含扩展名的文件名，用于构造对象路径。
    ///   - contentType: 文件的 MIME 类型。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证获取或上传失败、安全检查失败时抛出错误。
    func uploadImageWithSafetyCheck(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传本地图片文件并通过内容安全检查。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件 URL。
    ///   - contentType: 文件 MIME 类型；`nil` 时根据文件名推断。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 文件无效、凭证获取或上传失败、安全检查失败时抛出错误。
    func uploadImageFileWithSafetyCheck(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传视频数据。
    ///
    /// - Parameters:
    ///   - data: 编码后的视频文件数据。
    ///   - fileName: 包含扩展名的文件名，用于构造对象路径。
    ///   - contentType: 文件的 MIME 类型。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadVideo(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传本地视频文件。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地视频文件 URL。
    ///   - contentType: 文件 MIME 类型；`nil` 时根据文件名推断。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 文件无效、凭证获取或上传失败时抛出错误。
    func uploadVideoFile(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 将远端图片下载到本地文件。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载文件的远端 URL。
    ///   - destinationURL: 写入文件的本地目标 URL。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 写入完成的本地文件 URL 与字节数。
    /// - Throws: 地址无效、下载或文件写入失败，以及任务取消时抛出错误。
    func downloadImage(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile

    /// 将远端视频下载到本地文件。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载文件的远端 URL。
    ///   - destinationURL: 写入文件的本地目标 URL。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 写入完成的本地文件 URL 与字节数。
    /// - Throws: 地址无效、下载或文件写入失败，以及任务取消时抛出错误。
    func downloadVideo(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile
}
