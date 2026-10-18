//
//  XmaxStorageManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 文件存储公共入口，负责将服务层能力转换为公开 API。
final class XmaxStorageManager: XmaxStorageManaging, Sendable {

    /// 服务层组件
    private let storageService: any StorageServicing

    /// 使用指定存储服务创建文件管理组件。
    ///
    /// - Parameter storageService: 执行文件上传、下载和安全检查的服务。
    init(storageService: any StorageServicing) {
        self.storageService = storageService
    }

    /// 创建使用默认对象存储实现的文件管理组件。
    ///
    /// - Parameter apiService: 提供临时存储凭证和内容安全检查的 API 服务。
    convenience init(apiService: any ApiServicing) {
        self.init(
            storageService: StorageService(
                apiService: apiService,
                storageManager: StorageManager()
            )
        )
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadImage(
                data: data,
                fileName: fileName,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadImageFile(
                fileURL: fileURL,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadImageWithSafetyCheck(
                data: data,
                fileName: fileName,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadImageFileWithSafetyCheck(
                fileURL: fileURL,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadVideo(
                data: data,
                fileName: fileName,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadVideoFile(
                fileURL: fileURL,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxDownloadedFile {
        try await downloadedFile {
            try await storageService.downloadImage(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxDownloadedFile {
        try await downloadedFile {
            try await storageService.downloadVideo(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                progress: progressListener(progress)
            )
        }
    }
}

private extension XmaxStorageManager {
    /// 将字节进度转换为公开的文件进度回调。
    ///
    /// - Parameter handler: 接收 Progress 的回调；nil 表示不监听。
    /// - Returns: 供存储服务调用的字节进度监听器；未提供回调时返回 nil。
    func progressListener(
        _ handler: XmaxStorageProgressHandler?
    ) -> StorageProgressListener? {
        guard let handler else {
            return nil
        }
        return { completedBytes, totalBytes in
            let progress = Progress(totalUnitCount: totalBytes)
            progress.completedUnitCount = completedBytes
            handler(progress)
        }
    }

    /// 执行上传并转换为公开的上传结果。
    ///
    /// - Parameter operation: 返回服务层上传结果的异步操作。
    /// - Returns: 供接入方使用的远端文件信息。
    /// - Throws: 上传失败时抛出转换后的 XmaxError。
    func uploadedFile(
        _ operation: () async throws -> StoredFile
    ) async throws -> XmaxUploadedFile {
        do {
            let file = try await operation()
            return XmaxUploadedFile(
                url: file.url,
                objectKey: file.objectKey,
                etag: file.etag
            )
        } catch {
            throw XmaxError.from(error)
        }
    }

    /// 执行下载并转换为公开的下载结果。
    ///
    /// - Parameter operation: 返回服务层下载结果的异步操作。
    /// - Returns: 供接入方使用的本地文件信息。
    /// - Throws: 下载失败时抛出转换后的 XmaxError。
    func downloadedFile(
        _ operation: () async throws -> DownloadedFile
    ) async throws -> XmaxDownloadedFile {
        do {
            let file = try await operation()
            return XmaxDownloadedFile(
                fileURL: file.fileURL,
                byteCount: file.byteCount
            )
        } catch {
            throw XmaxError.from(error)
        }
    }
}
