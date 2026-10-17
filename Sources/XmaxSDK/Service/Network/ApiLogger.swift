//
//  ApiLogger.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 输出不包含认证信息的 API 调试日志，并在请求失败时记录响应正文。
enum ApiLogger {

    /// 记录 API 响应状态和耗时，失败时附带响应正文。
    ///
    /// - Parameters:
    ///   - method: 请求的 HTTP 方法。
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - statusCode: HTTP 响应状态码。
    ///   - bodyByteCount: 响应正文的字节数。
    ///   - durationMs: 请求耗时，单位为毫秒。
    ///   - successful: 请求及业务响应是否成功。
    ///   - responseBody: 失败响应正文；成功时不记录正文。
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

    /// 记录收到有效 HTTP 响应前发生的请求错误。
    ///
    /// - Parameters:
    ///   - method: 请求的 HTTP 方法。
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - error: 请求期间发生的错误。
    ///   - durationMs: 请求耗时，单位为毫秒。
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

    /// 生成包含响应元数据及可选正文的日志文本。
    ///
    /// - Parameters:
    ///   - method: 请求的 HTTP 方法。
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - statusCode: HTTP 响应状态码。
    ///   - bodyByteCount: 响应正文的字节数。
    ///   - durationMs: 请求耗时，单位为毫秒。
    ///   - responseBody: 需要输出的响应正文；`nil` 仅输出响应大小。
    /// - Returns: 使用当前日志语言的结构化响应日志文本。
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

    /// 将 JSON 正文格式化并缩进，其他正文按 UTF-8 文本输出。
    ///
    /// - Parameter data: 待格式化的响应正文。
    /// - Returns: 可打印的正文；无法按 UTF-8 解码时返回占位提示。
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
