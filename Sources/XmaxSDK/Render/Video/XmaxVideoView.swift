@preconcurrency import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import UIKit

/// 显示本地或远端实时视频轨道的 UIKit 容器。
///
/// 显示本地轨道时，所属窗口横竖屏切换会断开该轨道的实时连接，保留本地预览。
@MainActor
public final class XmaxVideoView: UIView {

    // 图片转换资源
    private static let imageContext = CIContext()

    // 公共配置
    /// 当前显示的视频轨道。
    public var track: RealtimeVideoTrack? {
        didSet {
            guard oldValue !== track else {
                return
            }
            displayOrientation = nil
            detach(track: oldValue)
            attachCurrentTrackIfNeeded()
            updateOrientationObservation()
            updateWindowOrientation()
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
    var frameDisplayHandler: (() -> Void)?

    // 所属窗口的显示方向
    private(set) var displayOrientation: UIInterfaceOrientation?
    private var orientationObserver: VideoOrientationObserver?

    // 视频预览
    private var decodedVideoLayer: AVSampleBufferDisplayLayer?
    private var decodedVideoTimebase: CMTimebase?
    private var nextDecodedVideoPresentationTime = CMTime.invalid

    // 本地预览缓冲资源
    private var localPreviewPixelBufferPool: CVPixelBufferPool?
    private var localPreviewFormat: VideoFormat?
    private var localPreviewFormatDescription: CMVideoFormatDescription?

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
    ///   - isInteractionEnabled: 是否允许在远端视频上进行轨迹交互。
    public init(
        track: RealtimeVideoTrack? = nil,
        videoContentMode: VideoContentMode = .fill,
        isInteractionEnabled: Bool = true
    ) {
        self.track = track
        self.videoContentMode = videoContentMode
        self.isInteractionEnabled = isInteractionEnabled
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
        displayOrientation = nil
        if window == nil {
            detachCurrentTrack()
        } else {
            attachCurrentTrackIfNeeded()
        }
        updateOrientationObservation()
        updateWindowOrientation()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        decodedVideoLayer?.frame = bounds
        trajectoryOverlayView.frame = bounds
        bringSubviewToFront(trajectoryOverlayView)
        updateWindowOrientation()
    }
}

extension XmaxVideoView {
    private func updateOrientationObservation() {
        var responder: UIResponder? = next
        while responder != nil && !(responder is UIViewController) {
            responder = responder?.next
        }
        let parent = window != nil && track?.orientationChangeHandler != nil
            ? responder as? UIViewController : nil
        guard orientationObserver?.parent !== parent else { return }

        if let observer = orientationObserver {
            observer.willMove(toParent: nil)
            observer.view.removeFromSuperview()
            observer.removeFromParent()
            orientationObserver = nil
        }
        guard let parent else { return }

        let observer = VideoOrientationObserver(videoView: self)
        orientationObserver = observer
        parent.addChild(observer)
        observer.view.frame = bounds
        observer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(observer.view)
        observer.didMove(toParent: parent)
    }

    func updateWindowOrientation() {
        guard orientationObserver?.isTransitioning != true,
              let scene = window?.windowScene else { return }
        if #available(iOS 26.0, *) {
            updateInterfaceOrientation(scene.effectiveGeometry.interfaceOrientation)
        } else {
            updateInterfaceOrientation(scene.interfaceOrientation)
        }
    }

    /// 同步完整显示方向；首次绑定和同轴旋转只调整采集，不触发断开。
    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        let next: CameraOrientation
        switch orientation {
        case .portrait: next = .portrait
        case .portraitUpsideDown: next = .portraitUpsideDown
        case .landscapeLeft: next = .landscapeLeft
        case .landscapeRight: next = .landscapeRight
        default: return
        }
        guard orientation != displayOrientation else { return }
        let changedAxis = displayOrientation.map { $0.isLandscape != next.isLandscape } ?? false
        displayOrientation = orientation
        track?.displayOrientation = next
        track?.orientationChangeHandler?(changedAxis)
    }

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
        frameDisplayHandler?()
    }

    func clearImageFrame() {
        imageView.image = nil
        imageView.isHidden = true
    }

    func prepareDecodedVideoPreview(contentMode: VideoContentMode) {
        let decodedVideoLayer: AVSampleBufferDisplayLayer
        if let currentLayer = self.decodedVideoLayer {
            decodedVideoLayer = currentLayer
        } else {
            decodedVideoLayer = AVSampleBufferDisplayLayer()
            // 视频内容跟随旋转布局立即更新，不叠加子图层的隐式缩放和翻转动画。
            decodedVideoLayer.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "transform": NSNull(),
                "videoGravity": NSNull()
            ]
            decodedVideoLayer.frame = bounds
            layer.insertSublayer(decodedVideoLayer, at: 0)
            self.decodedVideoLayer = decodedVideoLayer

            var timebase: CMTimebase?
            let status = CMTimebaseCreateWithSourceClock(
                allocator: kCFAllocatorDefault,
                sourceClock: CMClockGetHostTimeClock(),
                timebaseOut: &timebase
            )
            if status == noErr, let timebase {
                CMTimebaseSetTime(timebase, time: .zero)
                CMTimebaseSetRate(timebase, rate: 1)
                decodedVideoLayer.controlTimebase = timebase
                decodedVideoTimebase = timebase
            }
        }
        decodedVideoLayer.videoGravity = contentMode == .fit ?
            .resizeAspect : .resizeAspectFill
    }

    func setDecodedVideoPreviewMirrored(_ mirrored: Bool) {
        decodedVideoLayer?.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1))
    }

    func displayDecodedVideoFrame(
        _ frame: VideoFrame,
        contentMode: VideoContentMode
    ) {
        if decodedVideoLayer == nil {
            prepareDecodedVideoPreview(contentMode: contentMode)
        }
        guard let decodedVideoLayer,
              let decodedVideoTimebase else {
            return
        }
        decodedVideoLayer.videoGravity = contentMode == .fit ?
            .resizeAspect : .resizeAspectFill
        if decodedVideoLayer.requiresFlushToResumeDecoding {
            decodedVideoLayer.flush()
        }

        do {
            let formatChanged = localPreviewFormat != frame.format
            let pixelBuffer = try makeLocalPreviewPixelBuffer(frame)
            let formatDescription = try localPreviewDescription(for: pixelBuffer)
            let presentationTime = CMTimebaseGetTime(decodedVideoTimebase)
            var timing = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: presentationTime,
                decodeTimeStamp: .invalid
            )
            var sampleBuffer: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: formatDescription,
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            ) == noErr,
                  let sampleBuffer else {
                throw Self.invalidImageFrameError
            }
            CMSetAttachment(
                sampleBuffer,
                key: kCMSampleAttachmentKey_DisplayImmediately,
                value: kCFBooleanTrue,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
            )
            decodedVideoLayer.enqueue(sampleBuffer)
            if formatChanged {
                XmaxLogger.media.debug(
                    message: """
                    旋转时序 [TEMP] (Rotation Timing)
                    ├─ \(XmaxLogger.localized("阶段：", "Stage: "))preview_submitted
                    ├─ \(XmaxLogger.localized("时间：", "Time: "))\(DispatchTime.now().uptimeNanoseconds / 1000000) ms
                    └─ \(XmaxLogger.localized("分辨率：", "Resolution: "))\(frame.format.width) × \(frame.format.height)
                    """
                )
            }
            frameDisplayHandler?()
        } catch {
            Self.logRenderingFailure(
                title: "显示本地视频帧失败 (Failed to Display Local Video Frame)",
                error: error
            )
        }
    }

    func displayRemoteVideoFrame(
        _ frame: RealtimeVideoFrame,
        contentMode: VideoContentMode
    ) {
        if decodedVideoLayer == nil {
            prepareDecodedVideoPreview(contentMode: contentMode)
        }
        guard let decodedVideoLayer,
              let decodedVideoTimebase else {
            return
        }
        decodedVideoLayer.videoGravity = contentMode == .fit ?
            .resizeAspect : .resizeAspectFill
        if decodedVideoLayer.requiresFlushToResumeDecoding {
            decodedVideoLayer.flush()
            nextDecodedVideoPresentationTime = .invalid
        }

        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr,
              let formatDescription else {
            return
        }

        let currentTime = CMTimebaseGetTime(decodedVideoTimebase)
        let presentationTime: CMTime
        if nextDecodedVideoPresentationTime.isValid,
           nextDecodedVideoPresentationTime >= currentTime {
            presentationTime = nextDecodedVideoPresentationTime
        } else {
            presentationTime = currentTime
        }
        let duration = frame.duration.isValid && frame.duration > .zero ?
            frame.duration : CMTime(value: 1, timescale: 24)
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr,
              let sampleBuffer else {
            return
        }
        decodedVideoLayer.enqueue(sampleBuffer)
        nextDecodedVideoPresentationTime = presentationTime + duration
        frameDisplayHandler?()
    }

    func clearDecodedVideoPreview() {
        decodedVideoLayer?.flushAndRemoveImage()
        decodedVideoLayer?.controlTimebase = nil
        decodedVideoLayer?.removeFromSuperlayer()
        decodedVideoLayer = nil
        decodedVideoTimebase = nil
        nextDecodedVideoPresentationTime = .invalid
        localPreviewPixelBufferPool = nil
        localPreviewFormat = nil
        localPreviewFormatDescription = nil
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
                    title: "绑定视频渲染视图失败 (Failed to Attach Video Render View)",
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
                    title: "解除视频渲染视图失败 (Failed to Detach Video Render View)",
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
        title: String,
        error: any Error
    ) {
        XmaxLogger.render.error(
            message: "\(title)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))" +
                (error as NSError).localizedDescription
        )
    }

    static func makeImage(_ frame: VideoFrame) throws -> UIImage {
        if frame.format.pixelFormat == .nv12 {
            return try makeNV12Image(frame)
        }

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

    static func makeNV12Image(_ frame: VideoFrame) throws -> UIImage {
        let width = frame.format.width
        let height = frame.format.height
        let pixelBuffer = try makeNV12PixelBuffer(frame)

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(
            image,
            from: CGRect(x: 0, y: 0, width: width, height: height)
        ) else {
            throw invalidImageFrameError
        }
        return UIImage(cgImage: cgImage)
    }

    func makeLocalPreviewPixelBuffer(_ frame: VideoFrame) throws -> CVPixelBuffer {
        if localPreviewFormat != frame.format || localPreviewPixelBufferPool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferWidthKey as String: frame.format.width,
                kCVPixelBufferHeightKey as String: frame.format.height,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
            ]
            var pool: CVPixelBufferPool?
            guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess,
                  let pool else {
                throw Self.invalidImageFrameError
            }
            localPreviewPixelBufferPool = pool
            localPreviewFormat = frame.format
            localPreviewFormatDescription = nil
        }

        return try Self.makeNV12PixelBuffer(frame, pool: localPreviewPixelBufferPool)
    }

    func localPreviewDescription(for pixelBuffer: CVPixelBuffer) throws -> CMVideoFormatDescription {
        if let description = localPreviewFormatDescription,
           CMVideoFormatDescriptionMatchesImageBuffer(description, imageBuffer: pixelBuffer) {
            return description
        }

        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &description
        ) == noErr, let description else {
            throw Self.invalidImageFrameError
        }
        localPreviewFormatDescription = description
        return description
    }

    static func makeNV12PixelBuffer(
        _ frame: VideoFrame,
        pool: CVPixelBufferPool? = nil
    ) throws -> CVPixelBuffer {
        let width = frame.format.width
        let height = frame.format.height
        guard frame.format.pixelFormat == .nv12,
              width > 0,
              height > 0,
              width.isMultiple(of: 2),
              height.isMultiple(of: 2),
              frame.planes.count == 2 else {
            throw invalidImageFrameError
        }

        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        let status: CVReturn
        if let pool {
            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        } else {
            status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                attributes,
                &pixelBuffer
            )
        }
        guard status == kCVReturnSuccess, let pixelBuffer,
              CVPixelBufferGetWidth(pixelBuffer) == width,
              CVPixelBufferGetHeight(pixelBuffer) == height,
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            throw invalidImageFrameError
        }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) ==
                kCVReturnSuccess else {
            throw invalidImageFrameError
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        try copyPlane(
            frame.planes[0],
            rowByteCount: width,
            rowCount: height,
            destination: CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
            destinationStride: CVPixelBufferGetBytesPerRowOfPlane(
                pixelBuffer,
                0
            )
        )
        try copyPlane(
            frame.planes[1],
            rowByteCount: width,
            rowCount: height / 2,
            destination: CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1),
            destinationStride: CVPixelBufferGetBytesPerRowOfPlane(
                pixelBuffer,
                1
            )
        )
        return pixelBuffer
    }

    static func copyPlane(
        _ plane: VideoFramePlane,
        rowByteCount: Int,
        rowCount: Int,
        destination: UnsafeMutableRawPointer?,
        destinationStride: Int
    ) throws {
        let (sourceLength, sourceLengthOverflow) = plane.stride
            .multipliedReportingOverflow(by: rowCount)
        guard let destination,
              rowByteCount > 0,
              rowCount > 0,
              plane.stride >= rowByteCount,
              destinationStride >= rowByteCount,
              !sourceLengthOverflow,
              plane.byteLength >= sourceLength,
              plane.byteOffset <= plane.data.count - sourceLength else {
            throw invalidImageFrameError
        }

        plane.data.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { return }
            let sourceStart = source.advanced(by: plane.byteOffset)
            if plane.stride == rowByteCount, destinationStride == rowByteCount {
                memcpy(destination, sourceStart, sourceLength)
                return
            }
            for row in 0..<rowCount {
                memcpy(
                    destination.advanced(by: row * destinationStride),
                    sourceStart.advanced(by: row * plane.stride),
                    rowByteCount
                )
            }
        }
    }

    static var invalidImageFrameError: XmaxError {
        XmaxError(
            code: .mediaError,
            message: "Image preview frame is invalid"
        )
    }
}
