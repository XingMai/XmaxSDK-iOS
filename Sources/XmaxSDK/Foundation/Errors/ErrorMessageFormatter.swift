//
//  ErrorMessageFormatter.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Formats errors for logs and diagnostic displays.
enum ErrorMessageFormatter {

    /// Formats an error with its diagnostic code.
    ///
    /// - Parameter error: The error to format.
    ///
    /// - Returns: A readable error description.
    static func format(
        _ error: any Error
    ) -> String {
        if let xmaxError = error as? XmaxError {
            let apiCode =
                xmaxError.apiCode.map {
                    "，业务码 \($0)"
                } ?? ""
            let httpStatus =
                xmaxError.httpStatus.map {
                    "，HTTP \($0)"
                } ?? ""

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
