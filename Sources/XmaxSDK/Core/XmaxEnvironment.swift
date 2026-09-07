import Foundation

/// Xmax 服务环境。
public enum XmaxEnvironment: String, CaseIterable, Equatable, Sendable {

    /// 国内环境。
    case china

    /// 海外环境。
    case global
}

extension XmaxEnvironment {
    var apiBaseURL: URL {
        switch self {
        case .china:
            URL(string: "https://cloud.xmax.22duck.cn/open/api/v1")!
        case .global:
            URL(string: "https://api.xmax.cloud/open/api/v1")!
        }
    }
}
