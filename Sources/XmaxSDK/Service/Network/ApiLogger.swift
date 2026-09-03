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
            XmaxLogger.debug(category: "API", message: message)
        } else {
            XmaxLogger.error(category: "API", message: message)
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
            category: "API",
            message: "\(method.rawValue) \(path) 失败 (Request Failed)\n" +
                "├─ 耗时：\(durationMs) ms\n" +
                "└─ 原因：\(ErrorMessageFormatter.format(error))"
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
            "├─ 状态：\(statusCode)\n" +
            "├─ 耗时：\(durationMs) ms\n"
        guard let responseBody else {
            return prefix + "└─ 响应：\(bodyByteCount) bytes"
        }

        let body = formatResponseBody(responseBody)
        return prefix +
            "├─ 响应：\(bodyByteCount) bytes\n" +
            "└─ 正文：\n   \(body)"
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
