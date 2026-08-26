import Foundation

/// 接收媒体层产生的中性视频帧。
typealias MediaVideoFrameListener = @Sendable (VideoFrame) throws -> Void

/// 接收媒体层产生的中性音频帧。
typealias MediaAudioFrameListener = @Sendable (AudioFrame) throws -> Void
