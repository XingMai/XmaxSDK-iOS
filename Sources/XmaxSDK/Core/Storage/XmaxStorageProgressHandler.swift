import Foundation

/// 接收文件上传或下载进度。
public typealias XmaxStorageProgressHandler = @Sendable (Progress) -> Void
