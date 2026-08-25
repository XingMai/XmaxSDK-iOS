import Foundation
import UIKit

/// 定义从 UIKit 页面呈现系统图片选择器的能力。
@MainActor
protocol ImagePicking: Sendable {

    /// 选择一张图片并读取为二进制数据。
    func pickImage(
        from presentingViewController: UIViewController
    ) async throws -> Data
}
