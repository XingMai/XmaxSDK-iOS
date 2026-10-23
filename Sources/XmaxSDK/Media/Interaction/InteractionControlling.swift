//
//  InteractionControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for generation trajectory input.
protocol InteractionControlling: Sendable {

    /// Starts accepting interactions for a generation task.
    ///
    /// - Parameters:
    ///   - taskID: The generation task identifier.
    ///   - videoFormat: The resolved media format used as the fixed coordinate baseline.
    func startInteraction(
        taskID: String,
        videoFormat: RealtimeVideoFormat
    ) async

    /// Stops accepting interactions and clears the task.
    func stopInteraction() async

    /// Submits a touch trajectory.
    ///
    /// - Parameter frame: The view trajectory and viewport dimensions.
    func submitInteraction(
        _ frame: InteractionFrame
    ) async
}
