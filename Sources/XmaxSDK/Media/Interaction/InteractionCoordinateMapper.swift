//
//  InteractionCoordinateMapper.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 将渲染视口坐标映射到模型输入视频的像素坐标。
enum InteractionCoordinateMapper {
    /// 计算视频按指定缩放方式显示在视口中的区域。
    ///
    /// - Parameters:
    ///   - viewportSize: 渲染视口尺寸，单位为点。
    ///   - videoSize: 视频内容尺寸，单位为像素。
    ///   - contentMode: 视频填充或适应视口的方式。
    /// - Returns: 视频在视口坐标系中的显示区域；尺寸或缩放无效时返回 `nil`。
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

    /// 将视口触控位置映射为视频像素坐标。
    ///
    /// - Parameters:
    ///   - point: 触控点在视口中的位置。
    ///   - viewportSize: 渲染视口尺寸，单位为点。
    ///   - videoSize: 视频内容尺寸，单位为像素。
    ///   - contentMode: 视频缩放与裁剪方式。
    /// - Returns: 限制在有效像素范围内的坐标；输入无效或点击 fit 留白区域时返回 `nil`。
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
