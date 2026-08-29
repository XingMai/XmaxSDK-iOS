import Foundation

/// 保存实时视频轨道与底层渲染能力之间的内部绑定关系。
@MainActor
enum VideoRenderRegistry {

    // 渲染绑定
    private static var bindings: [ObjectIdentifier: VideoRenderBinding] = [:]

    static func register(
        _ track: RealtimeVideoTrack,
        binding: VideoRenderBinding
    ) {
        bindings[ObjectIdentifier(track)] = binding
    }

    static func unregister(_ track: RealtimeVideoTrack) {
        bindings.removeValue(forKey: ObjectIdentifier(track))
    }

    static func binding(
        for track: RealtimeVideoTrack
    ) -> VideoRenderBinding? {
        bindings[ObjectIdentifier(track)]
    }
}
