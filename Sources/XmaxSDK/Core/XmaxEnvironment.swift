//
//  XmaxEnvironment.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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

    // 服务地址
    /// 当前环境的通用 API 地址。
    var apiBaseURL: URL {
        switch self {
        case .china:
            URL(string: "https://cloud.xmax.22duck.cn/open/api/v1")!
        case .global:
            URL(string: "https://api.xmax.cloud/open/api/v1")!
        }
    }
}
