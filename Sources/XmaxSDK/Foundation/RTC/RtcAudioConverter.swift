//
//  RtcAudioConverter.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Validates 48 kHz mono PCM16 for external RTC audio.
enum RtcAudioConverter {

    /// Validates an audio frame's byte count.
    ///
    /// - Parameter frame: A 10 ms, 48 kHz mono PCM16 frame.
    ///
    /// - Returns: The validated PCM data.
    ///
    /// - Throws: An error if the byte count does not match the required frame format.
    static func convertFrame(
        _ frame: AudioFrame
    ) throws -> Data {
        let expectedByteCount =
            AudioFrame.samplesPerFrame * AudioFrame.channelCount * MemoryLayout<Int16>.size
        guard frame.data.count == expectedByteCount else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Audio frame must contain exactly \(expectedByteCount) bytes"
            )
        }
        return frame.data
    }
}
