import CoreGraphics
import XmaxSDK

enum RealtimeConst {
    /// 从本地缓存读取 XLab API Key 使用的键。
    static let apiKeyStorageKey = "xlab.realtime.apiKey"

    /// 触控动图模式发起生成时使用的默认提示词。
    static let defaultTouchAnimationPrompt = "让画面自然动起来"

    /// 图片和视频预览区域相对顶部安全区的间距。
    static let mediaPreviewTopInset: CGFloat = 68

    /// 本地视频预览的默认音量。
    static let defaultLocalAudioVolume: Float = 0.45

    /// 远端生成音频的默认播放音量。
    static let defaultRemoteAudioVolume: Float = 1

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
