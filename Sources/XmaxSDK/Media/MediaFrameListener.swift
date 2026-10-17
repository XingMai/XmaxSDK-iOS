//
//  MediaFrameListener.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 接收媒体层产生的中性视频帧。
typealias MediaVideoFrameListener = @Sendable (VideoFrame) throws -> Void

/// 接收媒体层产生的中性音频帧。
typealias MediaAudioFrameListener = @Sendable (AudioFrame) throws -> Void
