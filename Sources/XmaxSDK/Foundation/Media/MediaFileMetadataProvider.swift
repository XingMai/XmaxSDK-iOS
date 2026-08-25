@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

/// 使用 AVFoundation 读取本地媒体文件元数据。
final class MediaFileMetadataProvider: MediaFileMetadataProviding, Sendable {

    func readMetadata(fileURL: URL) async throws -> MediaFileMetadata {
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
                durationUs: Int64((durationSeconds * 1_000_000).rounded(.up)),
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

private extension MediaFileMetadataProvider {
    static func rotation(
        from transform: CGAffineTransform
    ) -> VideoRotation {
        let degrees = atan2(transform.b, transform.a) * 180 / .pi
        let normalized = (Int(degrees.rounded()) % 360 + 360) % 360
        let nearestQuarterTurn = ((normalized + 45) / 90 * 90) % 360
        return VideoRotation(rawValue: nearestQuarterTurn) ?? .rotation0
    }

    static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
