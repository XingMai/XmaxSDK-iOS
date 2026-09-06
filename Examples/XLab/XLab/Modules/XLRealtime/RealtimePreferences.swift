import Foundation
import XmaxSDK

enum RealtimePreferences {
    /// 从本地缓存读取 XLab API Key 使用的键。
    static let apiKeyStorageKey = "xlab.realtime.apiKey"

    /// 从本地缓存读取所选实时模型使用的键。
    private static let modelStorageKey = "xlab.realtime.model"

    /// XLab 当前选择的实时生成模型。
    static var selectedModel: RealtimeModel {
        get {
            guard let rawValue = UserDefaults.standard.string(
                forKey: modelStorageKey
            ) else {
                return .x2_0
            }
            return RealtimeModel(rawValue: rawValue) ?? .x2_0
        }
        set {
            UserDefaults.standard.set(
                newValue.rawValue,
                forKey: modelStorageKey
            )
        }
    }

    /// 摄像头采集使用的视频规格。
    ///
    /// iOS 26 及以上使用较小尺寸，以适配系统版本对应的处理能力限制。
    static var cameraVideoFormat: RealtimeVideoFormat {
        if #available(iOS 26.0, *) {
            RealtimeVideoFormat(width: 704, height: 1280, fps: 24)
        } else {
            RealtimeVideoFormat(width: 832, height: 1472, fps: 24)
        }
    }
}
