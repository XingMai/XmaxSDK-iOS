//
//  XmaxRealtimeVideoView.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// A UIKit container switching between local preview and remote generation.
@MainActor
public final class XmaxRealtimeVideoView: UIView {

    /// The local preview track.
    public var localTrack: RealtimeVideoTrack? {
        didSet {
            guard oldValue !== localTrack else {
                return
            }
            localVideoView.track = localTrack
        }
    }

    /// The remote generation track.
    ///
    /// A new remote track fades in after its first frame is submitted for display. Setting it to
    /// `nil` immediately restores local preview.
    public var remoteTrack: RealtimeVideoTrack? {
        didSet {
            guard oldValue !== remoteTrack else {
                return
            }
            updateRemoteTrack()
        }
    }

    /// The video content mode.
    public var videoContentMode: VideoContentMode = .fill {
        didSet {
            guard oldValue != videoContentMode else {
                return
            }
            localVideoView.videoContentMode = videoContentMode
            remoteVideoView.videoContentMode = videoContentMode
        }
    }

    /// Whether remote trajectory interaction is enabled.
    public var isInteractionEnabled = true {
        didSet {
            guard oldValue != isInteractionEnabled else {
                return
            }
            remoteVideoView.isInteractionEnabled = isInteractionEnabled
        }
    }

    /// The custom remote trajectory effect, or `nil` for the built-in effect.
    public var trajectoryRenderer: (any TrajectoryEffectRendering)? {
        get {
            remoteVideoView.trajectoryRenderer
        }
        set {
            remoteVideoView.trajectoryRenderer = newValue
        }
    }

    /// The persistent local preview view.
    private lazy var localVideoView = XmaxVideoView(
        videoContentMode: videoContentMode,
        isInteractionEnabled: false
    )

    /// The remote generation view.
    private lazy var remoteVideoView = XmaxVideoView(
        videoContentMode: videoContentMode,
        isInteractionEnabled: isInteractionEnabled
    )

    /// Creates a realtime video container.
    ///
    /// - Parameters:
    ///   - localTrack: The local track to preview continuously.
    ///   - remoteTrack: The remote track displayed over local preview.
    ///   - videoContentMode: The content mode for both local and remote video.
    ///   - isInteractionEnabled: Whether remote trajectory interaction is enabled.
    public init(
        localTrack: RealtimeVideoTrack? = nil,
        remoteTrack: RealtimeVideoTrack? = nil,
        videoContentMode: VideoContentMode = .fill,
        isInteractionEnabled: Bool = true
    ) {
        self.localTrack = localTrack
        self.remoteTrack = remoteTrack
        self.videoContentMode = videoContentMode
        self.isInteractionEnabled = isInteractionEnabled
        super.init(frame: .zero)
        configureView()
    }

    /// Creates a realtime video container with a frame.
    ///
    /// - Parameter frame: The initial view frame.
    public override init(
        frame: CGRect
    ) {
        localTrack = nil
        remoteTrack = nil
        super.init(frame: frame)
        configureView()
    }

    /// Creates a realtime video container from an archive.
    ///
    /// - Parameter coder: The archive decoder.
    public required init?(
        coder: NSCoder
    ) {
        localTrack = nil
        remoteTrack = nil
        super.init(coder: coder)
        configureView()
    }

    /// Lays out both video views to fill the container.
    public override func layoutSubviews() {
        super.layoutSubviews()
        localVideoView.frame = bounds
        remoteVideoView.frame = bounds
    }
}

private extension XmaxRealtimeVideoView {

    /// Configures the local and remote video layers.
    func configureView() {
        backgroundColor = .black
        clipsToBounds = true
        addSubview(localVideoView)
        addSubview(remoteVideoView)
        localVideoView.track = localTrack
        updateRemoteTrack()
    }

    /// Waits for a new remote track's first displayed frame.
    func updateRemoteTrack() {
        remoteVideoView.frameDisplayHandler = nil
        remoteVideoView.layer.removeAllAnimations()
        remoteVideoView.alpha = 0
        remoteVideoView.isHidden = true
        remoteVideoView.track = nil

        guard let remoteTrack else {
            return
        }
        remoteVideoView.frameDisplayHandler = { [weak self, weak remoteTrack] in
            guard let self,
                self.remoteTrack === remoteTrack
            else {
                return
            }
            showRemoteVideo()
        }
        remoteVideoView.track = remoteTrack
    }

    /// Fades in remote video after its first frame is submitted.
    func showRemoteVideo() {
        remoteVideoView.frameDisplayHandler = nil
        guard remoteVideoView.isHidden || remoteVideoView.alpha < 1 else {
            return
        }
        remoteVideoView.layer.removeAllAnimations()
        remoteVideoView.isHidden = false
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.remoteVideoView.alpha = 1
        }
    }
}
