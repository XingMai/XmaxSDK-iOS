//
//  RealtimeExternalVideoSource.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo

/// 接入方自行采集、解码或处理的视频源，仅提供视频。
///
/// 采集权限、设备启停及最终释放由接入方负责。SDK 绑定供帧并提供本地预览，
/// 不采集麦克风。生命周期方法在主线程执行，视频帧可以从后台队列同步提交。
@MainActor
public protocol RealtimeExternalVideoSource: AnyObject, Sendable {

    /// 接入方提供的视频尺寸、帧率及编码配置；单次绑定期间保持不变。
    var videoFormat: RealtimeVideoFormat { get }

    /// 绑定帧接收器并开始供帧，不等待生成完成。
    ///
    /// 按 `sink.videoFormat` 完成尺寸调整和供帧节奏控制，方向及镜像需应用到像素。
    /// 返回后表示绑定完成，不要求已提交首帧；即使尚未连接也应供帧以显示预览。
    /// - Parameter sink: 本次绑定的视频帧接收器。
    /// - Throws: 无法启动供帧时抛出错误；失败或取消后 SDK 会调用 `stop()`。
    func start(
        sink: any RealtimeExternalFrameSink
    ) async throws

    /// 解绑并停止向 SDK 供帧，清除保存的接收器；重复调用必须安全。
    /// 不代表 SDK 接管或释放接入方的摄像头、播放器。
    func stop() async
}

/// 接收单次外部源绑定的视频帧，解绑后自动丢弃迟到帧。
///
/// 提交时同步复制像素，返回后接入方可以复用缓冲区；提交过程中不得修改像素。
public protocol RealtimeExternalFrameSink: AnyObject, Sendable {

    /// 经过模型面积上限和 4 对齐处理的供帧规格，保留源声明的帧率和编码配置。
    var videoFormat: RealtimeVideoFormat { get }

    /// 当前绑定是否接收预览和生成用帧；断开实时连接后仍为 true，解绑或失败后为 false。
    var isRequestingFrames: Bool { get }

    /// 提交方向正确、尺寸符合 `videoFormat` 的视频帧，不额外旋转、镜像或缩放。
    ///
    /// - Parameters:
    ///   - pixelBuffer: NV12 video-range（420v）或 BGRA 像素缓冲区。
    ///   - timestamp: 非负、持续递增的单调时间戳；循环或跳转后不能回退。
    ///     无效、重复或倒退的时间戳会被忽略。
    func pushVideo(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    )

    /// 报告不可恢复的媒体源错误，SDK 将结束连接并释放本地流。
    ///
    /// - Parameter error: 采集、解码或处理过程中无法恢复的错误。
    func reportError(
        _ error: any Error
    )
}
