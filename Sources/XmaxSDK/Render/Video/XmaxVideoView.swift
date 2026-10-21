//
//  XmaxVideoView.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

    /// 将图片帧转换为可显示图像的共享上下文。
    private static let imageContext = CIContext()

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

    /// 当前已绑定渲染资源的视频轨道。
    private weak var attachedTrack: RealtimeVideoTrack?

    /// 当前绑定轨迹交互的媒体轨道。
    private weak var attachedTrajectoryTrack: RealtimeVideoTrack?

    /// 当前视图的轨迹交互绑定。
    private var attachedTrajectoryBinding: TrajectoryBinding?

    /// 接入方提供的轨迹效果渲染器。
    private var customTrajectoryRenderer:
        (any TrajectoryEffectRendering)?

    /// 视图提交有效视频帧后触发的内部回调。
    var frameDisplayHandler: (() -> Void)?

    /// 视图所在窗口当前的界面方向。
    private(set) var displayOrientation: UIInterfaceOrientation?

    /// 监听视图所在窗口的方向变化。
    private var orientationObserver: VideoOrientationObserver?

    /// 显示本地或远端解码帧的视频图层。
    private var decodedVideoLayer: AVSampleBufferDisplayLayer?

    /// 解码帧显示使用的播放时间基准。
    private var decodedVideoTimebase: CMTimebase?

    /// 下一解码帧的展示时间。
    private var nextDecodedVideoPresentationTime = CMTime.invalid

    /// 复用本地预览像素缓冲区。
    private var localPreviewPixelBufferPool: CVPixelBufferPool?

    /// 当前本地预览帧格式。
    private var localPreviewFormat: VideoFormat?

    /// 复用本地预览的媒体格式描述。
    private var localPreviewFormatDescription: CMVideoFormatDescription?

    /// 显示图片输入的本地预览。
    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isHidden = true
        return imageView
    }()

    /// 采集触摸并绘制轨迹的覆盖层。
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
    ///
    /// - Parameter frame: 视图初始布局区域。
    public override init(
        frame: CGRect
    ) {
        track = nil
        super.init(frame: frame)
        configureView()
    }

    /// 从 Interface Builder 归档恢复视频渲染容器。
    ///
    /// - Parameter coder: 视图归档解码器。
    public required init?(
        coder: NSCoder
    ) {
        track = nil
        super.init(coder: coder)
        configureView()
    }

    /// 随窗口挂载状态更新轨道绑定及方向观察。
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

    /// 同步视频图层和交互覆盖层布局，并更新窗口方向。
    public override func layoutSubviews() {
        super.layoutSubviews()
        decodedVideoLayer?.frame = bounds
        trajectoryOverlayView.frame = bounds
        bringSubviewToFront(trajectoryOverlayView)
        updateWindowOrientation()
    }
}

extension XmaxVideoView {

    /// 按当前轨道和所属控制器更新窗口旋转观察器。
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

    /// 在非旋转过渡期间同步窗口的实际显示方向。
    func updateWindowOrientation() {
        guard orientationObserver?.isTransitioning != true,
              let scene = window?.windowScene else { return }
        if #available(iOS 26.0, *) {
            updateInterfaceOrientation(scene.effectiveGeometry.interfaceOrientation)
        } else {
            updateInterfaceOrientation(scene.interfaceOrientation)
        }
    }

    /// 更新轨道显示方向，并通知横竖轴是否发生变化。
    ///
    /// - Parameter orientation: 目标界面方向；未知方向不处理。
    func updateInterfaceOrientation(
        _ orientation: UIInterfaceOrientation
    ) {
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

    /// 配置黑色背景、裁剪及图片和轨迹子视图。
    func configureView() {
        backgroundColor = .black
        clipsToBounds = true
        addSubview(imageView)
        addSubview(trajectoryOverlayView)
    }

    /// 将图片帧转换为图像并显示到静态预览。
    ///
    /// - Parameters:
    ///   - frame: BGRA 或 NV12 图片帧。
    ///   - contentMode: 图像的缩放与裁剪方式。
    /// - Throws: 帧布局无效或图像创建失败时抛出错误。
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

    /// 清空并隐藏静态图片预览。
    func clearImageFrame() {
        imageView.image = nil
        imageView.isHidden = true
    }

    /// 创建或更新解码视频图层及其显示时钟。
    ///
    /// - Parameter contentMode: 视频画面的缩放与裁剪方式。
    func prepareDecodedVideoPreview(
        contentMode: VideoContentMode
    ) {
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

    /// 设置解码视频预览的水平镜像。
    ///
    /// - Parameter mirrored: 是否水平镜像画面。
    func setDecodedVideoPreviewMirrored(
        _ mirrored: Bool
    ) {
        decodedVideoLayer?.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1))
    }

    /// 将本地 NV12 帧转换为样本并立即提交预览。
    ///
    /// - Parameters:
    ///   - frame: 待显示的本地视频帧。
    ///   - contentMode: 视频画面的缩放与裁剪方式。
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
            frameDisplayHandler?()
        } catch {
            Self.logRenderingFailure(
                title: "显示本地视频帧失败 (Failed to Display Local Video Frame)",
                error: error
            )
        }
    }

    /// 按帧时长提交远端画面。
    ///
    /// - Parameters:
    ///   - frame: 已完成插帧等处理的远端视频帧。
    ///   - contentMode: 视频画面的缩放与裁剪方式。
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

    /// 移除视频图层并释放显示时钟和预览缓冲资源。
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

    /// 在视图已挂载窗口时绑定当前轨道的画面和交互。
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

    /// 解除指定轨道在当前视图中的画面和交互绑定。
    ///
    /// - Parameter track: 需要解除的轨道；`nil` 时不执行操作。
    func detach(
        track: RealtimeVideoTrack?
    ) {
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

    /// 解除当前持有的全部视频和交互轨道绑定。
    func detachCurrentTrack() {
        let renderTrack = attachedTrack
        let trajectoryTrack = attachedTrajectoryTrack
        detach(track: renderTrack)
        if trajectoryTrack !== renderTrack {
            detach(track: trajectoryTrack)
        }
    }

    /// 输出带统一错误描述的渲染日志。
    ///
    /// - Parameters:
    ///   - title: 中英文日志标题。
    ///   - error: 需要记录的渲染错误。
    static func logRenderingFailure(
        title: String,
        error: any Error
    ) {
        XmaxLogger.render.error(
            message: "\(title)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))" +
                (error as NSError).localizedDescription
        )
    }

    /// 将 BGRA 或 NV12 视频帧转换为 UIKit 图像。
    ///
    /// - Parameter frame: 待转换的图片视频帧。
    /// - Returns: 包含原始像素内容的图像。
    /// - Throws: 像素格式、平面布局无效或图像创建失败时抛出错误。
    static func makeImage(
        _ frame: VideoFrame
    ) throws -> UIImage {
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

    /// 将 NV12 帧转换为可显示的 UIKit 图像。
    ///
    /// - Parameter frame: 双平面 NV12 视频帧。
    /// - Returns: 转换后的图像。
    /// - Throws: 缓冲区转换或图像创建失败时抛出错误。
    static func makeNV12Image(
        _ frame: VideoFrame
    ) throws -> UIImage {
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

    /// 复用符合当前帧规格的缓冲池创建预览缓冲区。
    ///
    /// - Parameter frame: 待复制的本地 NV12 视频帧。
    /// - Returns: 已填充当前帧数据的像素缓冲区。
    /// - Throws: 缓冲池创建或帧数据复制失败时抛出错误。
    func makeLocalPreviewPixelBuffer(
        _ frame: VideoFrame
    ) throws -> CVPixelBuffer {
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

    /// 复用或创建与像素缓冲区匹配的视频格式描述。
    ///
    /// - Parameter pixelBuffer: 当前预览像素缓冲区。
    /// - Returns: 与缓冲区尺寸和格式匹配的描述。
    /// - Throws: 视频格式描述创建失败时抛出错误。
    func localPreviewDescription(
        for pixelBuffer: CVPixelBuffer
    ) throws -> CMVideoFormatDescription {
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

    /// 校验并复制 NV12 帧到 IOSurface 像素缓冲区。
    ///
    /// - Parameters:
    ///   - frame: 待复制的 NV12 视频帧。
    ///   - pool: 可复用的像素缓冲池；`nil` 时单独分配。
    /// - Returns: 包含亮度及色度平面的像素缓冲区。
    /// - Throws: 帧布局无效、缓冲区分配、锁定或复制失败时抛出错误。
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

    /// 按行复制一个像素平面的有效数据。
    ///
    /// - Parameters:
    ///   - plane: 提供源数据和行步长的平面。
    ///   - rowByteCount: 每行需要复制的字节数。
    ///   - rowCount: 需要复制的行数。
    ///   - destination: 目标平面起始地址。
    ///   - destinationStride: 目标平面每行字节数。
    /// - Throws: 源数据或目标布局不能容纳指定区域时抛出错误。
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

    /// 图片帧数据不满足显示要求时返回的错误。
    static var invalidImageFrameError: XmaxError {
        XmaxError(
            code: .mediaError,
            message: "Image preview frame is invalid"
        )
    }
}
