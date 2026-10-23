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

/// The Xmax service environment.
public enum XmaxEnvironment: String, CaseIterable, Equatable, Sendable {

    /// The China service environment.
    case china

    /// The global service environment.
    case global
}

extension XmaxEnvironment {

    /// The base URL for general API requests in this environment.
    var apiBaseURL: URL {
        switch self {
        case .china:
            URL(string: "https://cloud.xmax.22duck.cn/open/api/v1")!
        case .global:
            URL(string: "https://api.xmax.cloud/open/api/v1")!
        }
    }

    /// The base URL for realtime session requests in this environment.
    var realtimeApiBaseURL: URL {
        switch self {
        case .china:
            apiBaseURL
        case .global:
            URL(string: "https://api.xmax.ai/open/api/v1")!
        }
    }
}
