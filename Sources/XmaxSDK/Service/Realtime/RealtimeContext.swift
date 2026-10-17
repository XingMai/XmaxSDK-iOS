//
//  RealtimeContext.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 单次实时生成任务的文本和参考资源上下文。
public struct RealtimeContext: Equatable, Sendable {

    // 生成条件
    /// 实时生成使用的文本条件。
    public let prompt: String

    /// 已上传参考图片的可选远端路径。
    public let referencePath: String?

    /// 创建实时生成条件，并去除文本与参考路径首尾空白。
    ///
    /// - Parameters:
    ///   - prompt: 实时生成的文本条件。
    ///   - referencePath: 参考图的远端路径；`nil` 或仅包含空白时不使用参考图。
    public init(
        prompt: String,
        referencePath: String? = nil
    ) {
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReferencePath = referencePath?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.referencePath = normalizedReferencePath?.isEmpty == false
            ? normalizedReferencePath
            : nil
    }
}
