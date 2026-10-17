//
//  RuntimeInfo.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Darwin
import Foundation

/// 描述 SDK 当前运行环境。
struct RuntimeInfo: Encodable, Sendable {

    // 运行环境信息
    let platform: String
    let osVersion: String
    let sdkVersion: String
    let deviceModel: String

    // 当前环境快照
    static let current = RuntimeInfo(
        platform: "ios",
        osVersion: currentOSVersion(),
        sdkVersion: XmaxSDKInfo.version,
        deviceModel: currentDeviceModel()
    )

    /// 定义运行环境字段在请求中的编码名称。
    enum CodingKeys: String, CodingKey {
        case platform
        case osVersion = "os_version"
        case sdkVersion = "sdk_version"
        case deviceModel = "device_model"
    }
}

private extension RuntimeInfo {
    /// 读取当前操作系统版本并省略零补丁号。
    ///
    /// - Returns: 以点分隔的系统主版本、次版本和可选补丁版本。
    static func currentOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var components = [
            String(version.majorVersion),
            String(version.minorVersion)
        ]
        if version.patchVersion > 0 {
            components.append(String(version.patchVersion))
        }
        return components.joined(separator: ".")
    }

    /// 读取设备机型标识，模拟器优先使用其目标机型。
    ///
    /// - Returns: 设备硬件标识；无法读取时返回 `unknown`。
    static func currentDeviceModel() -> String {
        if let simulatorModel = ProcessInfo.processInfo.environment[
            "SIMULATOR_MODEL_IDENTIFIER"
        ], !simulatorModel.isEmpty {
            return simulatorModel
        }

        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else {
            return "unknown"
        }
        let capacity = MemoryLayout.size(ofValue: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: capacity
            ) { String(cString: $0) }
        }
    }
}
