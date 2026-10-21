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

/// 校验 RTC 外部音频使用的 48 kHz、单声道 PCM16 数据。
enum RtcAudioConverter {

    /// 校验单帧 PCM 长度并返回可推送的音频数据。
    ///
    /// - Parameter frame: 48 kHz、单声道 PCM16 的 10 ms 音频帧。
    /// - Returns: 通过长度校验的原始 PCM 数据。
    /// - Throws: 音频数据长度不符合固定帧规格时抛出错误。
    static func convertFrame(
        _ frame: AudioFrame
    ) throws -> Data {
        let expectedByteCount = AudioFrame.samplesPerFrame * AudioFrame.channelCount * MemoryLayout<Int16>.size
        guard frame.data.count == expectedByteCount else {
            throw XmaxError(code: .invalidConfiguration, message: "Audio frame must contain exactly \(expectedByteCount) bytes")
        }
        return frame.data
    }
}
