import CoreGraphics

/// 将渲染视口坐标映射到模型输入视频的像素坐标。
enum InteractionCoordinateMapper {
    static func displayedFrame(
        viewportSize: CGSize,
        videoSize: CGSize,
        contentMode: VideoContentMode
    ) -> CGRect? {
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              videoSize.width > 0,
              videoSize.height > 0 else {
            return nil
        }

        let widthScale = viewportSize.width / videoSize.width
        let heightScale = viewportSize.height / videoSize.height
        let scale = contentMode == .fill
            ? max(widthScale, heightScale)
            : min(widthScale, heightScale)
        guard scale.isFinite, scale > 0 else { return nil }

        let displayedSize = CGSize(
            width: videoSize.width * scale,
            height: videoSize.height * scale
        )
        return CGRect(
            x: (viewportSize.width - displayedSize.width) / 2,
            y: (viewportSize.height - displayedSize.height) / 2,
            width: displayedSize.width,
            height: displayedSize.height
        )
    }

    static func map(
        _ point: CGPoint,
        viewportSize: CGSize,
        videoSize: CGSize,
        contentMode: VideoContentMode
    ) -> RealtimePoint? {
        guard point.x.isFinite,
              point.y.isFinite,
              let displayedFrame = displayedFrame(
                  viewportSize: viewportSize,
                  videoSize: videoSize,
                  contentMode: contentMode
              ) else {
            return nil
        }
        if contentMode == .fit, !displayedFrame.contains(point) {
            return nil
        }

        let scale = displayedFrame.width / videoSize.width
        guard scale.isFinite, scale > 0 else { return nil }
        let mappedX = ((point.x - displayedFrame.minX) / scale).rounded()
        let mappedY = ((point.y - displayedFrame.minY) / scale).rounded()
        return RealtimePoint(
            x: min(max(mappedX, 0), videoSize.width - 1),
            y: min(max(mappedY, 0), videoSize.height - 1)
        )
    }
}
