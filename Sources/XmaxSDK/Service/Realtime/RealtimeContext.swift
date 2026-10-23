//
//  RealtimeContext.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// The prompt and reference media for a generation task.
public struct RealtimeContext: Equatable, Sendable {

    /// The generation prompt.
    public let prompt: String

    /// The uploaded reference image's remote path, if used.
    public let referencePath: String?

    /// Creates generation conditions.
    ///
    /// - Parameters:
    ///   - prompt: The generation prompt.
    ///   - referencePath: The remote reference image path. `nil` or whitespace-only values omit the
    ///     reference.
    public init(
        prompt: String,
        referencePath: String? = nil
    ) {
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReferencePath = referencePath?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.referencePath =
            normalizedReferencePath?.isEmpty == false
            ? normalizedReferencePath
            : nil
    }
}
