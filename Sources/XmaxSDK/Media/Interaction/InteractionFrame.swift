import CoreGraphics

/// 一次从渲染视口采集到的交互输入。
struct InteractionFrame: Sendable {
    let points: [CGPoint]
    let viewportSize: CGSize
    let contentMode: VideoContentMode
}

extension RealtimeVideoFormat {
    var size: CGSize {
        CGSize(width: width, height: height)
    }
}
