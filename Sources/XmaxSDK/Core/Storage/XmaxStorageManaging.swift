//
//  XmaxStorageManaging.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 定义 SDK 对接入方提供的文件上传和下载能力。
public protocol XmaxStorageManaging: Sendable {

    /// 上传图片数据。
    ///
    /// - Parameters:
    ///   - data: 图片的文件编码数据。
    ///   - fileName: 包含扩展名的文件名，用于生成存储对象名。
    ///   - contentType: 文件的 MIME 类型，例如 image/jpeg。
    ///   - progress: 文件传输进度回调；nil 表示不接收进度。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadImage(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传本地图片文件。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件地址。
    ///   - contentType: 文件的 MIME 类型；nil 时根据文件名推断。
    ///   - progress: 文件传输进度回调；nil 表示不接收进度。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadImage(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传图片数据，并完成内容安全检查后返回结果。
    ///
    /// - Parameters:
    ///   - data: 图片的文件编码数据。
    ///   - fileName: 包含扩展名的文件名，用于生成存储对象名。
    ///   - contentType: 文件的 MIME 类型，例如 image/jpeg。
    ///   - progress: 文件传输进度回调；nil 表示不接收进度。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败、内容安全检查未通过时抛出错误。
    func uploadImageWithSafetyCheck(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传本地图片文件，并完成内容安全检查后返回结果。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件地址。
    ///   - contentType: 文件的 MIME 类型；nil 时根据文件名推断。
    ///   - progress: 文件传输进度回调；nil 表示不接收进度。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败、内容安全检查未通过时抛出错误。
    func uploadImageWithSafetyCheck(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传视频数据。
    ///
    /// - Parameters:
    ///   - data: 视频的文件编码数据。
    ///   - fileName: 包含扩展名的文件名，用于生成存储对象名。
    ///   - contentType: 文件的 MIME 类型，例如 video/mp4。
    ///   - progress: 文件传输进度回调；nil 表示不接收进度。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadVideo(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传本地视频文件。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地视频文件地址。
    ///   - contentType: 文件的 MIME 类型；nil 时根据文件名推断。
    ///   - progress: 文件传输进度回调；nil 表示不接收进度。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadVideo(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 下载图片到指定本地文件。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载图片的远端地址。
    ///   - destinationURL: 下载文件的本地保存地址。
    ///   - progress: 文件传输进度回调；nil 表示不接收进度。
    /// - Returns: 本地文件地址及下载字节数。
    /// - Throws: 地址无效、文件写入或下载失败时抛出错误。
    func downloadImage(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxDownloadedFile

    /// 下载视频到指定本地文件。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载视频的远端地址。
    ///   - destinationURL: 下载文件的本地保存地址。
    ///   - progress: 文件传输进度回调；nil 表示不接收进度。
    /// - Returns: 本地文件地址及下载字节数。
    /// - Throws: 地址无效、文件写入或下载失败时抛出错误。
    func downloadVideo(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxDownloadedFile
}

public extension XmaxStorageManaging {
    /// 上传图片数据。不接收进度通知。
    ///
    /// - Parameters:
    ///   - data: 图片的文件编码数据。
    ///   - fileName: 包含扩展名的文件名，用于生成存储对象名。
    ///   - contentType: 文件的 MIME 类型，例如 image/jpeg。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadImage(
        _ data: Data,
        fileName: String,
        contentType: String
    ) async throws -> XmaxUploadedFile {
        try await uploadImage(
            data,
            fileName: fileName,
            contentType: contentType,
            progress: nil
        )
    }

    /// 上传本地图片文件。不接收进度通知。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件地址。
    ///   - contentType: 文件的 MIME 类型；nil 时根据文件名推断。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadImage(
        at fileURL: URL,
        contentType: String? = nil
    ) async throws -> XmaxUploadedFile {
        try await uploadImage(
            at: fileURL,
            contentType: contentType,
            progress: nil
        )
    }

    /// 上传图片数据，并完成内容安全检查后返回结果。不接收进度通知。
    ///
    /// - Parameters:
    ///   - data: 图片的文件编码数据。
    ///   - fileName: 包含扩展名的文件名，用于生成存储对象名。
    ///   - contentType: 文件的 MIME 类型，例如 image/jpeg。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败、内容安全检查未通过时抛出错误。
    func uploadImageWithSafetyCheck(
        _ data: Data,
        fileName: String,
        contentType: String
    ) async throws -> XmaxUploadedFile {
        try await uploadImageWithSafetyCheck(
            data,
            fileName: fileName,
            contentType: contentType,
            progress: nil
        )
    }

    /// 上传本地图片文件，并完成内容安全检查后返回结果。不接收进度通知。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件地址。
    ///   - contentType: 文件的 MIME 类型；nil 时根据文件名推断。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败、内容安全检查未通过时抛出错误。
    func uploadImageWithSafetyCheck(
        at fileURL: URL,
        contentType: String? = nil
    ) async throws -> XmaxUploadedFile {
        try await uploadImageWithSafetyCheck(
            at: fileURL,
            contentType: contentType,
            progress: nil
        )
    }

    /// 上传视频数据。不接收进度通知。
    ///
    /// - Parameters:
    ///   - data: 视频的文件编码数据。
    ///   - fileName: 包含扩展名的文件名，用于生成存储对象名。
    ///   - contentType: 文件的 MIME 类型，例如 video/mp4。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadVideo(
        _ data: Data,
        fileName: String,
        contentType: String
    ) async throws -> XmaxUploadedFile {
        try await uploadVideo(
            data,
            fileName: fileName,
            contentType: contentType,
            progress: nil
        )
    }

    /// 上传本地视频文件。不接收进度通知。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地视频文件地址。
    ///   - contentType: 文件的 MIME 类型；nil 时根据文件名推断。
    /// - Returns: 上传文件的访问地址、对象标识和可用的实体标识。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
    func uploadVideo(
        at fileURL: URL,
        contentType: String? = nil
    ) async throws -> XmaxUploadedFile {
        try await uploadVideo(
            at: fileURL,
            contentType: contentType,
            progress: nil
        )
    }

    /// 下载图片到指定本地文件。不接收进度通知。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载图片的远端地址。
    ///   - destinationURL: 下载文件的本地保存地址。
    /// - Returns: 本地文件地址及下载字节数。
    /// - Throws: 地址无效、文件写入或下载失败时抛出错误。
    func downloadImage(
        from remoteURL: URL,
        to destinationURL: URL
    ) async throws -> XmaxDownloadedFile {
        try await downloadImage(
            from: remoteURL,
            to: destinationURL,
            progress: nil
        )
    }

    /// 下载视频到指定本地文件。不接收进度通知。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载视频的远端地址。
    ///   - destinationURL: 下载文件的本地保存地址。
    /// - Returns: 本地文件地址及下载字节数。
    /// - Throws: 地址无效、文件写入或下载失败时抛出错误。
    func downloadVideo(
        from remoteURL: URL,
        to destinationURL: URL
    ) async throws -> XmaxDownloadedFile {
        try await downloadVideo(
            from: remoteURL,
            to: destinationURL,
            progress: nil
        )
    }
}
