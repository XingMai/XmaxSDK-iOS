import UIKit

/// 管理远端 RTC 视频流与 UIKit 渲染视图之间的绑定关系。
@MainActor
final class RemoteVideoController: RemoteVideoControlling {

    // 基础层组件
    private let rtcProvider: any RtcProviding

    // 渲染资源
    private var remoteStream: RemoteStream?
    private weak var remoteView: UIView?
    private var remoteContentMode = VideoContentMode.fill

    init(rtcProvider: any RtcProviding) {
        self.rtcProvider = rtcProvider
    }

    func setRemoteStream(_ stream: RemoteStream?) throws {
        let previousStream = remoteStream
        if let previousStream, previousStream != stream {
            try rtcProvider.unbindRemoteVideo(previousStream)
        }

        remoteStream = stream
        guard let stream, let remoteView else {
            return
        }
        try rtcProvider.bindRemoteVideo(
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
            try rtcProvider.unbindRemoteVideo(remoteStream)
        }

        remoteView = view
        remoteContentMode = contentMode
        guard let remoteStream else {
            return
        }
        try rtcProvider.bindRemoteVideo(
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
            try rtcProvider.unbindRemoteVideo(remoteStream)
        }
    }

    func reset() throws {
        let stream = remoteStream
        remoteStream = nil
        remoteView = nil
        remoteContentMode = .fill

        if let stream {
            try rtcProvider.unbindRemoteVideo(stream)
        }
    }
}
