/// 中性视频帧支持的像素格式。
enum VideoPixelFormat: String, CaseIterable, Sendable {

    case i420
    case nv12
    case nv21
    case rgba
    case bgra
    case argb
}
