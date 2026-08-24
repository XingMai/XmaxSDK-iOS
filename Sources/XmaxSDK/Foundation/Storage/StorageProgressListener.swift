/// 接收存储任务已完成字节数和总字节数的进度回调。
typealias StorageProgressListener = @Sendable (
    _ completedBytes: Int64,
    _ totalBytes: Int64
) -> Void
