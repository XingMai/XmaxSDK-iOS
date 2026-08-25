import Foundation

/// 定义图片和视频的上传、下载及图片安全检查能力。
protocol StorageServicing: Sendable {

    /// 上传图片数据。
    func uploadImage(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传本地图片文件。
    func uploadImageFile(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传图片数据并执行内容安全检查。
    func uploadImageWithSafetyCheck(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传本地图片文件并执行内容安全检查。
    func uploadImageFileWithSafetyCheck(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传视频数据。
    func uploadVideo(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 上传本地视频文件。
    func uploadVideoFile(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// 下载图片到本地文件。
    func downloadImage(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile

    /// 下载视频到本地文件。
    func downloadVideo(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile
}
