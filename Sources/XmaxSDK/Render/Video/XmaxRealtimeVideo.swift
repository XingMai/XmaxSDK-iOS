//
//  XmaxRealtimeVideo.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import SwiftUI

/// A SwiftUI view switching between local preview and remote generation.
@MainActor
public struct XmaxRealtimeVideo: UIViewRepresentable {

    /// The local preview track.
    public let localTrack: RealtimeVideoTrack?

    /// The remote generation track.
    public let remoteTrack: RealtimeVideoTrack?

    /// The video content mode.
    public let videoContentMode: VideoContentMode

    /// Whether remote trajectory interaction is enabled.
    public let isInteractionEnabled: Bool

    /// Creates a SwiftUI realtime video view.
    public init(
        localTrack: RealtimeVideoTrack?,
        remoteTrack: RealtimeVideoTrack?,
        videoContentMode: VideoContentMode = .fill,
        isInteractionEnabled: Bool = true
    ) {
        self.localTrack = localTrack
        self.remoteTrack = remoteTrack
        self.videoContentMode = videoContentMode
        self.isInteractionEnabled = isInteractionEnabled
    }

    /// Creates the underlying UIKit video view.
    ///
    /// - Parameter context: The SwiftUI view creation context.
    ///
    /// - Returns: The realtime video view configured with local and remote tracks.
    public func makeUIView(
        context: Context
    ) -> XmaxRealtimeVideoView {
        XmaxRealtimeVideoView(
            localTrack: localTrack,
            remoteTrack: remoteTrack,
            videoContentMode: videoContentMode,
            isInteractionEnabled: isInteractionEnabled
        )
    }

    /// Updates the UIKit view's tracks and display settings.
    ///
    /// - Parameters:
    ///   - view: The SDK video view to update.
    ///   - context: The SwiftUI view update context.
    public func updateUIView(
        _ view: XmaxRealtimeVideoView,
        context: Context
    ) {
        view.videoContentMode = videoContentMode
        view.isInteractionEnabled = isInteractionEnabled
        view.localTrack = localTrack
        view.remoteTrack = remoteTrack
    }

    /// Detaches video tracks when SwiftUI removes the view.
    ///
    /// - Parameters:
    ///   - view: The SDK view being removed.
    ///   - coordinator: The SwiftUI coordinator, with no additional state.
    public static func dismantleUIView(
        _ view: XmaxRealtimeVideoView,
        coordinator: Void
    ) {
        view.localTrack = nil
        view.remoteTrack = nil
    }
}
