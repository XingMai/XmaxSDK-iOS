//
//  StorageManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 定义基础文件上传和下载能力。
protocol StorageManaging: Sendable {

    /// 使用临时凭证上传数据或本地文件。
    ///
    /// - Parameters:
    ///   - source: 待上传的二进制数据或本地文件。
    ///   - objectKey: 存储桶内的目标对象路径。
    ///   - contentType: 上传内容的 MIME 类型。
    ///   - configuration: 存储地址、桶和临时访问凭证。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证无效、上传失败或任务取消时抛出错误。
    func upload(
        source: StorageUploadSource,
        objectKey: String,
        contentType: String,
        configuration: StorageConfiguration,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 下载远端文件并写入指定本地位置。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载文件的远端 URL。
    ///   - destinationURL: 写入文件的本地目标 URL。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 写入完成的本地文件 URL 与字节数。
    /// - Throws: 地址无效、下载或文件写入失败，以及任务取消时抛出错误。
    func download(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile
}

extension StorageManaging {

    /// 上传数据或本地文件，不接收进度通知。
    ///
    /// - Parameters:
    ///   - source: 待上传的二进制数据或本地文件。
    ///   - objectKey: 存储桶内的目标对象路径。
    ///   - contentType: 上传内容的 MIME 类型。
    ///   - configuration: 存储地址、桶和临时访问凭证。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证无效、上传失败或任务取消时抛出错误。
    func upload(
        source: StorageUploadSource,
        objectKey: String,
        contentType: String,
        configuration: StorageConfiguration
    ) async throws -> StoredFile {
        try await upload(
            source: source,
            objectKey: objectKey,
            contentType: contentType,
            configuration: configuration,
            progress: nil
        )
    }

    /// 下载远端文件，不接收进度通知。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载文件的远端 URL。
    ///   - destinationURL: 写入文件的本地目标 URL。
    /// - Returns: 写入完成的本地文件 URL 与字节数。
    /// - Throws: 地址无效、下载或文件写入失败，以及任务取消时抛出错误。
    func download(
        remoteURL: URL,
        destinationURL: URL
    ) async throws -> DownloadedFile {
        try await download(
            remoteURL: remoteURL,
            destinationURL: destinationURL,
            progress: nil
        )
    }
}
