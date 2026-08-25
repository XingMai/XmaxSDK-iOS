import Foundation

/// 定义读取本地媒体文件元数据的能力。
protocol MediaFileMetadataProviding: Sendable {

    /// 读取视频尺寸、旋转、时长和音频轨道信息。
    func readMetadata(fileURL: URL) async throws -> MediaFileMetadata
}
