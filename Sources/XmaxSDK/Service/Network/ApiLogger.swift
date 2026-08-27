import Foundation

/// 输出不包含认证信息和响应正文的 API 调试日志。
enum ApiLogger {

    /// 记录 API 响应状态、耗时和数据大小。
    static func logResponse(
        method: ApiMethod,
        path: String,
        statusCode: Int,
        bodyByteCount: Int,
        durationMs: Int,
        successful: Bool
    ) {
        let message = responseMessage(
            method: method,
            path: path,
            statusCode: statusCode,
            bodyByteCount: bodyByteCount,
            durationMs: durationMs
        )
        if successful {
            XmaxLogger.debug(message, category: "API")
        } else {
            XmaxLogger.error(message, category: "API")
        }
    }

    /// 记录 API 请求在收到有效 HTTP 响应前发生的错误。
    static func logFailure(
        method: ApiMethod,
        path: String,
        error: any Error,
        durationMs: Int
    ) {
        XmaxLogger.error(
            "\(method.rawValue) \(path) 失败 (Request Failed)\n" +
                "├─ 耗时：\(durationMs) ms\n" +
                "└─ 原因：\(ErrorMessageFormatter.format(error))",
            category: "API"
        )
    }

    static func responseMessage(
        method: ApiMethod,
        path: String,
        statusCode: Int,
        bodyByteCount: Int,
        durationMs: Int
    ) -> String {
        "\(method.rawValue) \(path)\n" +
            "├─ 状态：\(statusCode)\n" +
            "├─ 耗时：\(durationMs) ms\n" +
            "└─ 响应：\(bodyByteCount) bytes"
    }
}
