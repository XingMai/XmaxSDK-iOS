//
//  RuntimeInfo.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Darwin
import Foundation

/// 描述 SDK 当前运行环境。
struct RuntimeInfo: Encodable, Sendable {

    /// SDK 运行的平台名称。
    let platform: String

    /// 操作系统版本。
    let osVersion: String

    /// XmaxSDK 版本。
    let sdkVersion: String

    /// 设备型号标识。
    let deviceModel: String

    /// 当前平台、系统、SDK 和设备信息快照。
    static let current = RuntimeInfo(
        platform: "ios",
        osVersion: currentOSVersion(),
        sdkVersion: XmaxSDKInfo.version,
        deviceModel: currentDeviceModel()
    )

    /// 定义运行环境字段在请求中的编码名称。
    enum CodingKeys: String, CodingKey {

        /// 客户端平台字段。
        case platform

        /// 操作系统版本字段。
        case osVersion = "os_version"

        /// SDK 版本字段。
        case sdkVersion = "sdk_version"

        /// 设备型号字段。
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
