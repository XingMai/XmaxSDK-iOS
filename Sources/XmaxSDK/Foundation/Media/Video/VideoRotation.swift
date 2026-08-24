/// 视频帧需要顺时针旋转的角度。
enum VideoRotation: Int, CaseIterable, Sendable {
    case rotation0 = 0
    case rotation90 = 90
    case rotation180 = 180
    case rotation270 = 270
}
