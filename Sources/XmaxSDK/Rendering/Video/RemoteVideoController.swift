import UIKit

/// 管理远端 RTC 视频流与 UIKit 渲染视图之间的绑定关系。
@MainActor
final class RemoteVideoController: RemoteVideoControlling {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 渲染资源
    private var remoteStream: RemoteStream?
    private weak var remoteView: UIView?
    private var remoteContentMode = VideoContentMode.fill

    init(rtcManager: any RtcManaging) {
        self.rtcManager = rtcManager
    }

    func setRemoteStream(_ stream: RemoteStream?) throws {
        let previousStream = remoteStream
        if let previousStream, previousStream != stream {
            try rtcManager.unbindRemoteVideo(previousStream)
        }

        remoteStream = stream
        guard let stream, let remoteView else {
            return
        }
        try rtcManager.bindRemoteVideo(
            stream,
            to: remoteView,
            contentMode: remoteContentMode
        )
    }

    func attach(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        if let remoteView,
           remoteView !== view,
           let remoteStream {
            try rtcManager.unbindRemoteVideo(remoteStream)
        }

        remoteView = view
        remoteContentMode = contentMode
        guard let remoteStream else {
            return
        }
        try rtcManager.bindRemoteVideo(
            remoteStream,
            to: view,
            contentMode: contentMode
        )
    }

    func detach() throws {
        guard remoteView != nil else {
            return
        }
        remoteView = nil
        if let remoteStream {
            try rtcManager.unbindRemoteVideo(remoteStream)
        }
    }

    func reset() throws {
        let stream = remoteStream
        remoteStream = nil
        remoteView = nil
        remoteContentMode = .fill

        if let stream {
            try rtcManager.unbindRemoteVideo(stream)
        }
    }
}
