import Foundation

/// 定义 SDK 对接入方提供的文件上传和下载能力。
public protocol XmaxStorageManaging: Sendable {

    /// 上传图片数据。
    func uploadImage(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传本地图片文件。
    func uploadImage(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传图片数据并执行内容安全检查。
    func uploadImageWithSafetyCheck(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传本地图片文件并执行内容安全检查。
    func uploadImageWithSafetyCheck(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传视频数据。
    func uploadVideo(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 上传本地视频文件。
    func uploadVideo(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// 下载图片到本地文件。
    func downloadImage(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxDownloadedFile

    /// 下载视频到本地文件。
    func downloadVideo(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxDownloadedFile
}

public extension XmaxStorageManaging {
    /// 上传图片数据，不监听上传进度。
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

    /// 上传本地图片文件，不监听上传进度。
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

    /// 上传图片数据并执行内容安全检查，不监听上传进度。
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

    /// 上传本地图片文件并执行内容安全检查，不监听上传进度。
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

    /// 上传视频数据，不监听上传进度。
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

    /// 上传本地视频文件，不监听上传进度。
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

    /// 下载图片到本地文件，不监听下载进度。
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

    /// 下载视频到本地文件，不监听下载进度。
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
