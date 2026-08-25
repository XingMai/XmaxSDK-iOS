/// 持有一次已解码图片并提供缩放和编码能力。
protocol ImageProcessingSession: Sendable {

    /// 当前图片的显示尺寸和内容类型。
    var metadata: ImageProcessingMetadata { get }

    /// 缩放到指定尺寸，并优先使用请求的内容类型编码。
    func resizeAndEncode(
        width: Int,
        height: Int,
        requestedContentType: String,
        quality: Int
    ) throws -> ImageProcessingResult

    /// 按指定质量重新编码为 JPEG。
    func encodeJPEG(quality: Int) throws -> ImageProcessingResult

    /// 居中裁剪并转换为可供外部视频源重复使用的像素数据。
    func makeVideoFrameData(
        width: Int,
        height: Int
    ) throws -> ImageVideoFrameData
}
