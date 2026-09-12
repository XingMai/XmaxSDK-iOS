import Foundation

/// 输出不包含认证信息的 API 调试日志，并在请求失败时记录响应正文。
enum ApiLogger {

    /// 记录 API 响应状态、耗时、数据大小及失败响应正文。
    static func logResponse(
        method: ApiMethod,
        path: String,
        statusCode: Int,
        bodyByteCount: Int,
        durationMs: Int,
        successful: Bool,
        responseBody: Data? = nil
    ) {
        let message = responseMessage(
            method: method,
            path: path,
            statusCode: statusCode,
            bodyByteCount: bodyByteCount,
            durationMs: durationMs,
            responseBody: successful ? nil : responseBody
        )
        if successful {
            XmaxLogger.api.debug(message: message)
        } else {
            XmaxLogger.api.error(message: message)
        }
    }

    /// 记录 API 请求在收到有效 HTTP 响应前发生的错误。
    static func logFailure(
        method: ApiMethod,
        path: String,
        error: any Error,
        durationMs: Int
    ) {
        XmaxLogger.api.error(
            message: "\(method.rawValue) \(path) 失败 (Request Failed)\n" +
                "├─ \(XmaxLogger.localized("耗时：", "Duration: "))\(durationMs) ms\n" +
                "└─ \(XmaxLogger.localized("原因：", "Reason: "))\(ErrorMessageFormatter.format(error))"
        )
    }

    static func responseMessage(
        method: ApiMethod,
        path: String,
        statusCode: Int,
        bodyByteCount: Int,
        durationMs: Int,
        responseBody: Data? = nil
    ) -> String {
        let prefix = "\(method.rawValue) \(path)\n" +
            "├─ \(XmaxLogger.localized("状态：", "Status: "))\(statusCode)\n" +
            "├─ \(XmaxLogger.localized("耗时：", "Duration: "))\(durationMs) ms\n"
        guard let responseBody else {
            return prefix + "└─ \(XmaxLogger.localized("响应：", "Response Size: "))\(bodyByteCount) bytes"
        }

        let body = formatResponseBody(responseBody)
        return prefix +
            "├─ \(XmaxLogger.localized("响应：", "Response Size: "))\(bodyByteCount) bytes\n" +
            "└─ \(XmaxLogger.localized("正文：", "Response Body: "))\n   \(body)"
    }

    static func formatResponseBody(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formattedData = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let formattedBody = String(
                  data: formattedData,
                  encoding: .utf8
              ) else {
            return String(data: data, encoding: .utf8) ??
                "<Non-UTF-8 response body>"
        }
        return formattedBody.replacingOccurrences(
            of: "\n",
            with: "\n   "
        )
    }
}
