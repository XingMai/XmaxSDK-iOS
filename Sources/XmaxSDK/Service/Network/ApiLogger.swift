//
//  ApiLogger.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Logs API metadata and failed responses without authentication details.
enum ApiLogger {

    /// Logs API status and duration, including response contents on failure.
    ///
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - path: The path relative to the API root.
    ///   - statusCode: The HTTP response status.
    ///   - bodyByteCount: The response byte count.
    ///   - durationMs: The request duration, in milliseconds.
    ///   - successful: Whether the HTTP and business response succeeded.
    ///   - responseBody: The failure response body; successful bodies are not logged.
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

    /// Logs failures before an HTTP response is received.
    ///
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - path: The path relative to the API root.
    ///   - error: The request error.
    ///   - durationMs: The request duration, in milliseconds.
    static func logFailure(
        method: ApiMethod,
        path: String,
        error: any Error,
        durationMs: Int
    ) {
        XmaxLogger.api.error(
            message: "\(method.rawValue) \(path) 失败 (Request Failed)\n"
                + "├─ \(XmaxLogger.localized("耗时：", "Duration: "))\(durationMs) ms\n"
                + "└─ \(XmaxLogger.localized("原因：", "Reason: "))\(ErrorMessageFormatter.format(error))"
        )
    }

    /// Formats response metadata and an optional body.
    ///
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - path: The path relative to the API root.
    ///   - statusCode: The HTTP response status.
    ///   - bodyByteCount: The response byte count.
    ///   - durationMs: The request duration, in milliseconds.
    ///   - responseBody: The response body, or `nil` to include its size only.
    ///
    /// - Returns: The structured response log with localized labels.
    static func responseMessage(
        method: ApiMethod,
        path: String,
        statusCode: Int,
        bodyByteCount: Int,
        durationMs: Int,
        responseBody: Data? = nil
    ) -> String {
        let prefix =
            "\(method.rawValue) \(path)\n"
            + "├─ \(XmaxLogger.localized("状态：", "Status: "))\(statusCode)\n"
            + "├─ \(XmaxLogger.localized("耗时：", "Duration: "))\(durationMs) ms\n"
        guard let responseBody else {
            return prefix
                + "└─ \(XmaxLogger.localized("响应：", "Response Size: "))\(bodyByteCount) bytes"
        }

        let body = formatResponseBody(responseBody)
        return prefix
            + "├─ \(XmaxLogger.localized("响应：", "Response Size: "))\(bodyByteCount) bytes\n"
            + "└─ \(XmaxLogger.localized("正文：", "Response Body: "))\n   \(body)"
    }

    /// Formats JSON with indentation, or other data as UTF-8.
    ///
    /// - Parameter data: The response body to format.
    ///
    /// - Returns: The printable response, or a placeholder if not UTF-8.
    static func formatResponseBody(
        _ data: Data
    ) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            JSONSerialization.isValidJSONObject(object),
            let formattedData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let formattedBody = String(
                data: formattedData,
                encoding: .utf8
            )
        else {
            return String(
                data: data,
                encoding: .utf8
            ) ?? "<Non-UTF-8 response body>"
        }
        return formattedBody.replacingOccurrences(
            of: "\n",
            with: "\n   "
        )
    }
}
