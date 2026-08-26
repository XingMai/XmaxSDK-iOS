import Foundation

/// 定义基础文件上传和下载能力。
protocol StorageManaging: Sendable {

    /// 使用临时存储配置上传二进制数据或本地文件。
    func upload(
        source: StorageUploadSource,
        objectKey: String,
        contentType: String,
        configuration: StorageConfiguration,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 下载远端文件并写入指定本地位置。
    func download(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile
}

extension StorageManaging {

    /// 不监听进度地上传二进制数据或本地文件。
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

    /// 不监听进度地下载远端文件。
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
