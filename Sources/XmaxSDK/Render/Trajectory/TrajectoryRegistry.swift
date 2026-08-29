import Foundation

/// 保存远端视频轨道与轨迹交互能力之间的绑定。
@MainActor
enum TrajectoryRegistry {
    private static var bindings: [ObjectIdentifier: TrajectoryBinding] = [:]

    static func register(
        _ track: RealtimeVideoTrack,
        binding: TrajectoryBinding
    ) {
        bindings[ObjectIdentifier(track)] = binding
    }

    static func unregister(_ track: RealtimeVideoTrack) {
        bindings.removeValue(forKey: ObjectIdentifier(track))?.invalidate()
    }

    static func binding(for track: RealtimeVideoTrack) -> TrajectoryBinding? {
        bindings[ObjectIdentifier(track)]
    }
}
