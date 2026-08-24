import Foundation

/// 将 SDK、系统和第三方错误转换为适合日志及调试界面展示的文本。
enum ErrorMessageFormatter {

    /// 格式化指定错误，并保留可用于定位问题的稳定错误码。
    ///
    /// - Parameter error: 待格式化的错误。
    /// - Returns: 可读的错误说明。
    static func format(_ error: any Error) -> String {
        if let xmaxError = error as? XmaxError {
            let apiCode = xmaxError.apiCode.map { "，业务码 \($0)" } ?? ""
            let httpStatus = xmaxError.httpStatus.map { "，HTTP \($0)" } ?? ""

            return "\(xmaxError.message)（\(xmaxError.code.rawValue)\(apiCode)\(httpStatus)）"
        }

        let platformError = error as NSError
        let message = platformError.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !message.isEmpty {
            return "\(message)（平台错误码：\(platformError.code)）"
        }

        return "平台请求失败（平台错误码：\(platformError.code)）"
    }
}
