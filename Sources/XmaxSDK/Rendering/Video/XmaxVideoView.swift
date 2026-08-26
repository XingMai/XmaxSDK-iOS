import UIKit

/// 显示本地或远端实时视频轨道的 UIKit 容器。
@MainActor
public final class XmaxVideoView: UIView {

    // 公共配置
    /// 当前显示的视频轨道。
    public var track: RealtimeVideoTrack? {
        didSet {
            guard oldValue !== track else {
                return
            }
            detach(track: oldValue)
            attachCurrentTrackIfNeeded()
        }
    }

    /// 视频内容在容器中的显示模式。
    public var videoContentMode: VideoContentMode = .fill {
        didSet {
            guard oldValue != videoContentMode else {
                return
            }
            attachCurrentTrackIfNeeded()
        }
    }

    /// 是否允许在远端视频上绘制并发送轨迹交互。
    ///
    /// 交互默认开启，但只有生成任务启动后才会向服务端发送轨迹。
    public var isInteractionEnabled = true {
        didSet {
            guard oldValue != isInteractionEnabled else { return }
            trajectoryOverlayView.setRequestedInteractionEnabled(
                isInteractionEnabled
            )
        }
    }

    /// 自定义轨迹视觉效果；设置为 `nil` 时恢复 SDK 内置效果。
    ///
    /// 自定义渲染器只负责视觉表现，不会改变轨迹采样、坐标映射或发送。
    public var trajectoryRenderer:
        (any TrajectoryEffectRendering)? {
        get { customTrajectoryRenderer }
        set {
            customTrajectoryRenderer = newValue
            trajectoryOverlayView.setRenderer(
                newValue ?? DefaultTrajectoryEffectRenderer()
            )
        }
    }

    // 渲染状态
    private weak var attachedTrack: RealtimeVideoTrack?
    private weak var attachedTrajectoryTrack: RealtimeVideoTrack?
    private var attachedTrajectoryBinding: TrajectoryBinding?
    private var customTrajectoryRenderer:
        (any TrajectoryEffectRendering)?

    // 图片预览
    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isHidden = true
        return imageView
    }()

    // 轨迹交互
    private lazy var trajectoryOverlayView: TrajectoryOverlayView = {
        let overlayView = TrajectoryOverlayView(
            renderer: DefaultTrajectoryEffectRenderer()
        )
        overlayView.frame = bounds
        overlayView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight,
        ]
        overlayView.setRequestedInteractionEnabled(isInteractionEnabled)
        return overlayView
    }()

    /// 创建视频渲染容器。
    ///
    /// - Parameters:
    ///   - track: 需要显示的视频轨道；可以稍后设置。
    ///   - videoContentMode: 视频内容显示模式。
    public init(
        track: RealtimeVideoTrack? = nil,
        videoContentMode: VideoContentMode = .fill
    ) {
        self.track = track
        self.videoContentMode = videoContentMode
        super.init(frame: .zero)
        configureView()
    }

    /// 使用指定布局区域创建视频渲染容器。
    public override init(frame: CGRect) {
        track = nil
        super.init(frame: frame)
        configureView()
    }

    /// 从 Interface Builder 恢复视频渲染容器。
    public required init?(coder: NSCoder) {
        track = nil
        super.init(coder: coder)
        configureView()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            detachCurrentTrack()
        } else {
            attachCurrentTrackIfNeeded()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        trajectoryOverlayView.frame = bounds
        bringSubviewToFront(trajectoryOverlayView)
    }
}

extension XmaxVideoView {
    func configureView() {
        backgroundColor = .black
        clipsToBounds = true
        addSubview(imageView)
        addSubview(trajectoryOverlayView)
    }

    func displayImageFrame(
        _ frame: VideoFrame,
        contentMode: VideoContentMode
    ) throws {
        imageView.image = try Self.makeImage(frame)
        imageView.contentMode = contentMode == .fit ?
            .scaleAspectFit : .scaleAspectFill
        imageView.isHidden = false
        bringSubviewToFront(imageView)
        bringSubviewToFront(trajectoryOverlayView)
    }

    func clearImageFrame() {
        imageView.image = nil
        imageView.isHidden = true
    }

    func attachCurrentTrackIfNeeded() {
        guard window != nil, let track else {
            return
        }

        if let binding = VideoRenderRegistry.binding(for: track) {
            do {
                try binding.attach(
                    to: self,
                    contentMode: videoContentMode
                )
                attachedTrack = track
            } catch {
                attachedTrack = nil
                Self.logRenderingFailure(
                    operation: "绑定视频渲染视图",
                    error: error
                )
            }
        }

        if let trajectoryBinding = TrajectoryRegistry.binding(for: track) {
            trajectoryBinding.attach(
                to: trajectoryOverlayView,
                contentMode: videoContentMode
            )
            attachedTrajectoryTrack = track
            attachedTrajectoryBinding = trajectoryBinding
        }
        bringSubviewToFront(trajectoryOverlayView)
    }

    func detach(track: RealtimeVideoTrack?) {
        guard let track else { return }

        if attachedTrack === track {
            do {
                try VideoRenderRegistry.binding(for: track)?.detach(from: self)
            } catch {
                Self.logRenderingFailure(
                    operation: "解除视频渲染视图",
                    error: error
                )
            }
            attachedTrack = nil
        }

        if attachedTrajectoryTrack === track {
            attachedTrajectoryBinding?.detach(
                from: trajectoryOverlayView
            )
            attachedTrajectoryTrack = nil
            attachedTrajectoryBinding = nil
        }
    }

    func detachCurrentTrack() {
        let renderTrack = attachedTrack
        let trajectoryTrack = attachedTrajectoryTrack
        detach(track: renderTrack)
        if trajectoryTrack !== renderTrack {
            detach(track: trajectoryTrack)
        }
    }

    static func logRenderingFailure(
        operation: String,
        error: any Error
    ) {
        XmaxLogger.error(
            "\(operation)失败\n└─ 原因：" +
                (error as NSError).localizedDescription,
            category: "Rendering"
        )
    }

    static func makeImage(_ frame: VideoFrame) throws -> UIImage {
        let width = frame.format.width
        let height = frame.format.height
        let (minimumBytesPerRow, rowByteCountOverflow) = width
            .multipliedReportingOverflow(by: 4)
        guard frame.planes.count == 1 else {
            throw Self.invalidImageFrameError
        }
        let plane = frame.planes[0]
        let (requiredByteCount, byteCountOverflow) = plane.stride
            .multipliedReportingOverflow(by: height)
        guard frame.format.pixelFormat == .bgra,
              width > 0,
              height > 0,
              !rowByteCountOverflow,
              plane.stride >= minimumBytesPerRow,
              plane.byteOffset == 0,
              !byteCountOverflow,
              plane.byteLength >= requiredByteCount,
              plane.data.count >= requiredByteCount,
              let provider = CGDataProvider(
                  data: plane.data as CFData
              ) else {
            throw Self.invalidImageFrameError
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: plane.stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw XmaxError(
                code: .mediaError,
                message: "Failed to create the image preview"
            )
        }
        return UIImage(cgImage: image)
    }

    static var invalidImageFrameError: XmaxError {
        XmaxError(
            code: .mediaError,
            message: "Image preview frame is invalid"
        )
    }
}
