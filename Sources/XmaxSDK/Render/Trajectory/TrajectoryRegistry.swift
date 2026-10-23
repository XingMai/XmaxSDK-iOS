//
//  TrajectoryRegistry.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A registry of remote track interaction bindings.
@MainActor
enum TrajectoryRegistry {

    /// The interaction bindings keyed by video track identifier.
    private static var bindings: [ObjectIdentifier: TrajectoryBinding] = [:]

    /// Registers a remote track's interaction binding.
    ///
    /// - Parameters:
    ///   - track: The remote track to register.
    ///   - binding: The trajectory interaction binding.
    static func register(
        _ track: RealtimeVideoTrack,
        binding: TrajectoryBinding
    ) {
        bindings[ObjectIdentifier(track)] = binding
    }

    /// Removes and deactivates a track's interaction binding.
    ///
    /// - Parameter track: The remote track to unregister.
    static func unregister(
        _ track: RealtimeVideoTrack
    ) {
        bindings.removeValue(forKey: ObjectIdentifier(track))?.invalidate()
    }

    /// Returns a track's interaction binding.
    ///
    /// - Parameter track: The remote track to find.
    ///
    /// - Returns: The registered binding, or `nil`.
    static func binding(
        for track: RealtimeVideoTrack
    ) -> TrajectoryBinding? {
        bindings[ObjectIdentifier(track)]
    }
}
