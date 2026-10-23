//
//  TrajectoryBinding.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// Connects rendering touch input to media interactions.
final class TrajectoryBinding: @unchecked Sendable {

    /// The asynchronous interaction frame handler.
    private let interactionListener: RenderInteractionListener

    /// The attached trajectory overlay.
    @MainActor private weak var overlayView: TrajectoryOverlayView?

    /// The media content mode for coordinate mapping.
    @MainActor private var contentMode: VideoContentMode = .fill

    /// The resolved media dimensions for trajectory mapping.
    private let resolvedMediaSize: CGSize

    /// Creates a trajectory interaction binding.
    init(
        interactionListener: @escaping RenderInteractionListener,
        resolvedMediaSize: CGSize
    ) {
        self.interactionListener = interactionListener
        self.resolvedMediaSize = resolvedMediaSize
    }

    /// Attaches an overlay with its coordinate mapping configuration.
    ///
    /// - Parameters:
    ///   - overlayView: The overlay receiving touch input.
    ///   - contentMode: The video content mode.
    @MainActor
    func attach(
        to overlayView: TrajectoryOverlayView,
        contentMode: VideoContentMode
    ) {
        if self.overlayView !== overlayView {
            self.overlayView?.setBinding(nil)
            self.overlayView = overlayView
        }
        self.contentMode = contentMode
        overlayView.setBinding(self)
        overlayView.setContentMode(contentMode)
        overlayView.setResolvedMediaSize(resolvedMediaSize)
    }

    /// Detaches a trajectory overlay.
    ///
    /// - Parameter overlayView: The overlay to detach.
    @MainActor
    func detach(
        from overlayView: TrajectoryOverlayView
    ) {
        guard self.overlayView === overlayView else {
            return
        }
        self.overlayView = nil
        overlayView.setBinding(nil)
    }

    /// Invalidates and detaches the current trajectory overlay.
    @MainActor
    func invalidate() {
        overlayView?.setBinding(nil)
        overlayView = nil
    }

    /// Updates interaction mapping for a video content mode.
    ///
    /// - Parameter contentMode: The new video content mode.
    @MainActor
    func update(
        contentMode: VideoContentMode
    ) {
        self.contentMode = contentMode
        overlayView?.setContentMode(contentMode)
    }

    /// Delivers sampled viewport positions as an interaction frame.
    ///
    /// - Parameters:
    ///   - points: The sampled viewport positions.
    ///   - viewportSize: The viewport dimensions at sampling time.
    @MainActor
    func submit(
        points: [CGPoint],
        viewportSize: CGSize
    ) {
        guard !points.isEmpty else {
            return
        }
        let frame = InteractionFrame(
            points: points,
            viewportSize: viewportSize,
            contentMode: contentMode
        )
        let interactionListener = interactionListener
        Task {
            await interactionListener(frame)
        }
    }
}
