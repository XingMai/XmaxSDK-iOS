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

/// The SDK runtime environment.
struct RuntimeInfo: Encodable, Sendable {

    /// The platform name.
    let platform: String

    /// The operating system version.
    let osVersion: String

    /// The XmaxSDK version.
    let sdkVersion: String

    /// The device model identifier.
    let deviceModel: String

    /// A snapshot of platform, operating system, SDK, and device information.
    static let current = RuntimeInfo(
        platform: "ios",
        osVersion: currentOSVersion(),
        sdkVersion: XmaxSDKInfo.version,
        deviceModel: currentDeviceModel()
    )

    /// The encoded runtime field names.
    enum CodingKeys: String, CodingKey {

        /// The platform field.
        case platform

        /// The operating system version field.
        case osVersion = "os_version"

        /// The SDK version field.
        case sdkVersion = "sdk_version"

        /// The device model field.
        case deviceModel = "device_model"
    }
}

private extension RuntimeInfo {

    /// Returns the operating system version without a zero patch component.
    ///
    /// - Returns: The dotted major, minor, and optional patch version.
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

    /// Returns the hardware identifier, using the simulated device model when available.
    ///
    /// - Returns: The hardware identifier, or `unknown` if unavailable.
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
            ) {
                String(cString: $0)
            }
        }
    }
}
