//
//  MediaFileMetadataManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// 使用 AVFoundation 读取本地媒体文件元数据。
final class MediaFileMetadataManager: MediaFileMetadataManaging, Sendable {

    /// 读取视频的原始尺寸、显示旋转、时长和音频轨道信息。
    ///
    /// - Parameter fileURL: 可读取的本地视频文件 URL。
    /// - Returns: 用于准备本地视频流的媒体元数据。
    /// - Throws: 文件不可读、无视频轨道或媒体元数据无效时抛出错误。
    func readMetadata(
        fileURL: URL
    ) async throws -> MediaFileMetadata {
        guard fileURL.isFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw Self.mediaError("Media file does not exist")
        }

        let asset = AVURLAsset(url: fileURL)
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw Self.mediaError(
                    "The media file does not contain a video track"
                )
            }
            async let naturalSize = videoTrack.load(.naturalSize)
            async let preferredTransform = videoTrack.load(
                .preferredTransform
            )
            async let duration = asset.load(.duration)
            async let audioTracks = asset.loadTracks(withMediaType: .audio)

            let resolvedSize = try await naturalSize
            let resolvedTransform = try await preferredTransform
            let resolvedDuration = try await duration
            let resolvedAudioTracks = try await audioTracks
            let width = Int(abs(resolvedSize.width).rounded())
            let height = Int(abs(resolvedSize.height).rounded())
            let durationSeconds = resolvedDuration.seconds

            guard width > 0,
                  height > 0,
                  durationSeconds.isFinite,
                  durationSeconds > 0,
                  durationSeconds <= Double(Int64.max) / 1_000_000 else {
                throw Self.mediaError("Media file metadata is invalid")
            }

            return MediaFileMetadata(
                width: width,
                height: height,
                rotation: Self.rotation(from: resolvedTransform),
                durationSeconds: durationSeconds,
                hasAudio: !resolvedAudioTracks.isEmpty
            )
        } catch let error as XmaxError {
            throw error
        } catch {
            throw Self.mediaError(
                "Failed to read media metadata: " +
                    (error as NSError).localizedDescription
            )
        }
    }
}

private extension MediaFileMetadataManager {

    /// 将媒体轨道变换转换为最接近的四分之一圈旋转方向。
    ///
    /// - Parameter transform: 视频轨道的首选显示变换。
    /// - Returns: 归一化后的 0、90、180 或 270 度旋转。
    static func rotation(
        from transform: CGAffineTransform
    ) -> VideoRotation {
        let degrees = atan2(transform.b, transform.a) * 180 / .pi
        let normalized = (Int(degrees.rounded()) % 360 + 360) % 360
        let nearestQuarterTurn = ((normalized + 45) / 90 * 90) % 360
        return VideoRotation(rawValue: nearestQuarterTurn) ?? .rotation0
    }

    /// 创建媒体读取错误。
    ///
    /// - Parameter message: 可读的媒体错误说明。
    /// - Returns: 带有指定说明的媒体错误。
    static func mediaError(
        _ message: String
    ) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
