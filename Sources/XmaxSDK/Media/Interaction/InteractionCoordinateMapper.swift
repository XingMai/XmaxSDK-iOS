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

/// 将渲染视口坐标映射到固定媒体基准的像素坐标。
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
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              videoSize.width.isFinite, videoSize.height.isFinite,
              viewportSize.width > 0,
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

    /// 根据实际画面显示区域归一化触控位置，再映射到固定媒体尺寸。
    ///
    /// - Parameters:
    ///   - point: 触控点在视口中的位置。
    ///   - viewportSize: 渲染视口尺寸，单位为点。
    ///   - displayedVideoSize: 当前显示帧的像素尺寸，用于确定画面显示区域。
    ///   - mediaSize: 固定媒体基准的像素尺寸，用于计算发送坐标。
    ///   - contentMode: 视频缩放与裁剪方式。
    /// - Returns: 限制在有效像素范围内的坐标；输入无效或点击 fit 留白区域时返回 `nil`。
    static func map(
        _ point: CGPoint,
        viewportSize: CGSize,
        displayedVideoSize: CGSize,
        mediaSize: CGSize,
        contentMode: VideoContentMode
    ) -> RealtimePoint? {
        guard point.x.isFinite,
              point.y.isFinite,
              mediaSize.width.isFinite, mediaSize.height.isFinite,
              mediaSize.width >= 1, mediaSize.height >= 1,
              let displayedFrame = displayedFrame(
                  viewportSize: viewportSize,
                  videoSize: displayedVideoSize,
                  contentMode: contentMode
              ) else {
            return nil
        }
        if contentMode == .fit, !displayedFrame.contains(point) {
            return nil
        }

        let normalizedX = (point.x - displayedFrame.minX) / displayedFrame.width
        let normalizedY = (point.y - displayedFrame.minY) / displayedFrame.height
        let mappedX = (normalizedX * mediaSize.width).rounded()
        let mappedY = (normalizedY * mediaSize.height).rounded()
        return RealtimePoint(
            x: min(max(mappedX, 0), mediaSize.width - 1),
            y: min(max(mappedY, 0), mediaSize.height - 1)
        )
    }
}
