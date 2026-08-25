import UIKit

/// 将实时视频轨道绑定到具体 UIKit 渲染视图。
@MainActor
final class VideoRenderBinding {

    // 渲染信息
    let libraryName: String

    // 渲染操作
    private let attachHandler: (UIView, VideoContentMode) throws -> Void
    private let detachHandler: () throws -> Void

    // 运行状态
    private weak var attachedView: UIView?

    init(
        libraryName: String,
        attachHandler: @escaping (UIView, VideoContentMode) throws -> Void,
        detachHandler: @escaping () throws -> Void
    ) {
        self.libraryName = libraryName
        self.attachHandler = attachHandler
        self.detachHandler = detachHandler
    }

    func attach(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        if let attachedView, attachedView !== view {
            try detachHandler()
            self.attachedView = nil
        }

        try attachHandler(view, contentMode)
        attachedView = view
    }

    func detach(from view: UIView) throws {
        guard attachedView === view else {
            return
        }
        try detach()
    }

    func detach() throws {
        guard attachedView != nil else {
            return
        }
        try detachHandler()
        attachedView = nil
    }
}
