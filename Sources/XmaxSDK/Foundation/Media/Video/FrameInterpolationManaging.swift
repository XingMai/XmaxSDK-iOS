//
//  FrameInterpolationManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia

/// An interface for single-frame interpolation.
protocol FrameInterpolationManaging: AnyObject, Sendable {

    /// Checks whether the processor matches an input frame.
    ///
    /// - Parameter frame: The frame to compare.
    ///
    /// - Returns: `true` if dimensions and pixel format match.
    func matches(
        _ frame: RealtimeVideoFrame
    ) -> Bool

    /// Generates an intermediate frame between the previous and current frames.
    ///
    /// - Parameters:
    ///   - frame: The current decoded video frame.
    ///   - sourceDuration: The current source frame's display duration.
    ///
    /// - Returns: The original first frame, or an interpolated frame followed by the current frame.
    ///
    /// - Throws: An error if buffer preparation or VideoToolbox processing fails.
    func process(
        _ frame: RealtimeVideoFrame,
        sourceDuration: CMTime
    ) async throws -> [RealtimeVideoFrame]

    /// Closes interpolation and releases retained frames.
    func close() async
}
