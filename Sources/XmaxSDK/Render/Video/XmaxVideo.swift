//
//  XmaxVideo.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import SwiftUI

/// A SwiftUI view displaying a local or remote video track.
@MainActor
public struct XmaxVideo: UIViewRepresentable {

    /// The displayed track, or `nil` for an empty container.
    public let track: RealtimeVideoTrack?

    /// The video content mode.
    public let videoContentMode: VideoContentMode

    /// Whether remote trajectory interaction is enabled.
    public let isInteractionEnabled: Bool

    /// Creates a SwiftUI video view.
    public init(
        track: RealtimeVideoTrack?,
        videoContentMode: VideoContentMode = .fill,
        isInteractionEnabled: Bool = true
    ) {
        self.track = track
        self.videoContentMode = videoContentMode
        self.isInteractionEnabled = isInteractionEnabled
    }

    /// Creates the underlying UIKit video view.
    ///
    /// - Parameter context: The SwiftUI view creation context.
    ///
    /// - Returns: The SDK view configured for the current track.
    public func makeUIView(
        context: Context
    ) -> XmaxVideoView {
        let view = XmaxVideoView(
            track: track,
            videoContentMode: videoContentMode,
            isInteractionEnabled: isInteractionEnabled
        )
        return view
    }

    /// Updates the UIKit view's tracks and display settings.
    ///
    /// - Parameters:
    ///   - view: The SDK video view to update.
    ///   - context: The SwiftUI view update context.
    public func updateUIView(
        _ view: XmaxVideoView,
        context: Context
    ) {
        view.videoContentMode = videoContentMode
        view.isInteractionEnabled = isInteractionEnabled
        view.track = track
    }

    /// Detaches video tracks when SwiftUI removes the view.
    ///
    /// - Parameters:
    ///   - view: The SDK view being removed.
    ///   - coordinator: The SwiftUI coordinator, with no additional state.
    public static func dismantleUIView(
        _ view: XmaxVideoView,
        coordinator: Void
    ) {
        view.track = nil
    }
}
