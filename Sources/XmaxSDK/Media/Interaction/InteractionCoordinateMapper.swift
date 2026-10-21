//
//  InteractionCoordinateMapper.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 将渲染视口坐标映射到固定媒体基准的归一化坐标。
enum InteractionCoordinateMapper {

    /// 按处理后的媒体比例和缩放方式计算视口中的媒体区域。
    ///
    /// - Parameters:
    ///   - viewportSize: 渲染视口尺寸，单位为点。
    ///   - resolvedMediaSize: 经尺寸上限与对齐处理的媒体尺寸，单位为像素。
    ///   - contentMode: 视频填充或适应视口的方式。
    /// - Returns: 视频在视口坐标系中的显示区域；尺寸或缩放无效时返回 `nil`。
    static func displayedFrame(
        viewportSize: CGSize,
        resolvedMediaSize: CGSize,
        contentMode: VideoContentMode
    ) -> CGRect? {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              resolvedMediaSize.width.isFinite, resolvedMediaSize.height.isFinite,
              viewportSize.width > 0,
              viewportSize.height > 0,
              resolvedMediaSize.width >= 1,
              resolvedMediaSize.height >= 1 else {
            return nil
        }

        let widthScale = viewportSize.width / resolvedMediaSize.width
        let heightScale = viewportSize.height / resolvedMediaSize.height
        let scale = contentMode == .fill
            ? max(widthScale, heightScale)
            : min(widthScale, heightScale)
        guard scale.isFinite, scale > 0 else { return nil }

        let displayedSize = CGSize(
            width: resolvedMediaSize.width * scale,
            height: resolvedMediaSize.height * scale
        )
        return CGRect(
            x: (viewportSize.width - displayedSize.width) / 2,
            y: (viewportSize.height - displayedSize.height) / 2,
            width: displayedSize.width,
            height: displayedSize.height
        )
    }

    /// 根据处理后的媒体比例，计算触控位置在完整媒体中的归一化坐标。
    ///
    /// - Parameters:
    ///   - point: 触控点在视口中的位置。
    ///   - viewportSize: 渲染视口尺寸，单位为点。
    ///   - resolvedMediaSize: 经尺寸上限与对齐处理的媒体尺寸，作为归一化坐标基准。
    ///   - contentMode: 视频缩放与裁剪方式。
    /// - Returns: 范围为 `[0, 1]` 的媒体归一化坐标；输入无效或点击 fit 留白区域时返回 `nil`。
    static func map(
        _ point: CGPoint,
        viewportSize: CGSize,
        resolvedMediaSize: CGSize,
        contentMode: VideoContentMode
    ) -> RealtimePoint? {
        guard point.x.isFinite,
              point.y.isFinite,
              let displayedFrame = displayedFrame(
                  viewportSize: viewportSize,
                  resolvedMediaSize: resolvedMediaSize,
                  contentMode: contentMode
              ) else {
            return nil
        }
        if contentMode == .fit, !displayedFrame.contains(point) {
            return nil
        }

        let normalizedX = (point.x - displayedFrame.minX) / displayedFrame.width
        let normalizedY = (point.y - displayedFrame.minY) / displayedFrame.height
        return RealtimePoint(
            x: min(max(normalizedX, 0), 1),
            y: min(max(normalizedY, 0), 1)
        )
    }
}
