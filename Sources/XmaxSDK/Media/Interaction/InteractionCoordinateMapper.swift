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

/// Maps viewport positions to normalized media coordinates.
enum InteractionCoordinateMapper {

    /// Resolves the displayed media rectangle from media aspect ratio and content mode.
    ///
    /// - Parameters:
    ///   - viewportSize: The viewport dimensions, in points.
    ///   - resolvedMediaSize: The resolved media dimensions, in pixels.
    ///   - contentMode: The video content mode.
    ///
    /// - Returns: The media rectangle in viewport coordinates, or `nil` for invalid dimensions or
    ///   scale.
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
            resolvedMediaSize.height >= 1
        else {
            return nil
        }

        let widthScale = viewportSize.width / resolvedMediaSize.width
        let heightScale = viewportSize.height / resolvedMediaSize.height
        let scale =
            contentMode == .fill
            ? max(
                widthScale,
                heightScale
            )
            : min(
                widthScale,
                heightScale
            )
        guard scale.isFinite, scale > 0 else {
            return nil
        }

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

    /// Resolves a touch position in normalized media coordinates.
    ///
    /// - Parameters:
    ///   - point: The touch position in the viewport.
    ///   - viewportSize: The viewport dimensions, in points.
    ///   - resolvedMediaSize: The resolved media dimensions used for normalization.
    ///   - contentMode: The video content mode.
    ///
    /// - Returns: Coordinates in `[0, 1]`, or `nil` for invalid input or touches in aspect-fit
    ///   margins.
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
            )
        else {
            return nil
        }

        if contentMode == .fit, !displayedFrame.contains(point) {
            return nil
        }

        let normalizedX = (point.x - displayedFrame.minX) / displayedFrame.width
        let normalizedY = (point.y - displayedFrame.minY) / displayedFrame.height
        return RealtimePoint(
            x: min(
                max(
                    normalizedX,
                    0
                ),
                1
            ),
            y: min(
                max(
                    normalizedY,
                    0
                ),
                1
            )
        )
    }
}
