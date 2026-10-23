//
//  MediaFileMetadataManagingStub.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@testable import XmaxSDK

struct MediaFileMetadataManagingStub: MediaFileMetadataManaging {
    let metadata: MediaFileMetadata
    var error: (any Error)?

    init(
        metadata: MediaFileMetadata = MediaFileMetadata(
            width: 832, height: 1472, rotation: .rotation0,
            durationSeconds: 5, hasAudio: true
        ),
        error: (any Error)? = nil
    ) {
        self.metadata = metadata
        self.error = error
    }

    func readMetadata(fileURL: URL) async throws -> MediaFileMetadata {
        if let error { throw error }
        return metadata
    }
}
