//
//  XmaxEnvironment.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Xmax 服务环境。
public enum XmaxEnvironment: String, CaseIterable, Equatable, Sendable {

    /// 国内环境。
    case china

    /// 海外环境。
    case global
}

extension XmaxEnvironment {

    /// 当前环境的通用 API 地址。
    var apiBaseURL: URL {
        switch self {
        case .china:
            URL(string: "https://cloud.xmax.22duck.cn/open/api/v1")!
        case .global:
            URL(string: "https://api.xmax.cloud/open/api/v1")!
        }
    }

    /// 当前环境的实时会话 API 地址。
    var realtimeApiBaseURL: URL {
        switch self {
        case .china:
            apiBaseURL
        case .global:
            URL(string: "https://api.xmax.ai/open/api/v1")!
        }
    }
}
