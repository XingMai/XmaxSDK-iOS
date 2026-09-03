import Darwin
import Foundation

/// 描述 SDK 当前运行环境。
struct RuntimeInfo: Encodable, Sendable {
    let platform: String
    let osVersion: String
    let sdkVersion: String
    let deviceModel: String

    static let current = RuntimeInfo(
        platform: "ios",
        osVersion: currentOSVersion(),
        sdkVersion: XmaxSDKInfo.version,
        deviceModel: currentDeviceModel()
    )

    enum CodingKeys: String, CodingKey {
        case platform
        case osVersion = "os_version"
        case sdkVersion = "sdk_version"
        case deviceModel = "device_model"
    }
}

private extension RuntimeInfo {
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
