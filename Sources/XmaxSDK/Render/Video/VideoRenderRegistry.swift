//
//  VideoRenderRegistry.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A registry of video track rendering bindings.
@MainActor
enum VideoRenderRegistry {

    /// The bindings keyed by track identifier.
    private static var bindings: [ObjectIdentifier: VideoRenderBinding] = [:]

    /// Registers a video track's rendering binding.
    ///
    /// - Parameters:
    ///   - track: The video track to register.
    ///   - binding: The track's rendering binding.
    static func register(
        _ track: RealtimeVideoTrack,
        binding: VideoRenderBinding
    ) {
        bindings[ObjectIdentifier(track)] = binding
    }

    /// Removes a video track's rendering binding.
    ///
    /// - Parameter track: The video track to unregister.
    static func unregister(
        _ track: RealtimeVideoTrack
    ) {
        bindings.removeValue(forKey: ObjectIdentifier(track))
    }

    /// Returns a video track's rendering binding.
    ///
    /// - Parameter track: The video track to find.
    ///
    /// - Returns: The registered binding, or `nil`.
    static func binding(
        for track: RealtimeVideoTrack
    ) -> VideoRenderBinding? {
        bindings[ObjectIdentifier(track)]
    }
}
