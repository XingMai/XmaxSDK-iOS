//
//  VideoFramePlane.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A plane of video pixel data.
struct VideoFramePlane: Equatable, Sendable {

    /// The bytes containing this plane.
    let data: Data

    /// The byte stride between pixel rows.
    let stride: Int

    /// The plane's byte offset within the data.
    let byteOffset: Int

    /// The plane's byte count.
    let byteLength: Int

    /// Creates a plane referencing a valid byte range.
    ///
    /// - Parameters:
    ///   - data: The nonempty pixel data.
    ///   - stride: The positive row stride, in bytes.
    ///   - byteOffset: The plane's starting byte offset.
    ///   - byteLength: The plane's byte count, or `nil` to use all remaining data.
    ///
    /// - Throws: A configuration error if data is empty, its range is invalid, or its row stride is
    ///   not positive.
    init(
        data: Data,
        stride: Int,
        byteOffset: Int = 0,
        byteLength: Int? = nil
    ) throws {
        guard !data.isEmpty,
            byteOffset >= 0,
            byteOffset < data.count
        else {
            throw Self.invalidRangeError
        }

        let resolvedByteLength = byteLength ?? data.count - byteOffset
        guard resolvedByteLength > 0,
            resolvedByteLength <= data.count - byteOffset
        else {
            throw Self.invalidRangeError
        }
        guard stride > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame plane stride must be a positive integer"
            )
        }

        self.data = data
        self.stride = stride
        self.byteOffset = byteOffset
        self.byteLength = resolvedByteLength
    }

    /// The error for an invalid plane byte range.
    private static var invalidRangeError: XmaxError {
        XmaxError(
            code: .invalidConfiguration,
            message: "Video frame plane range is invalid"
        )
    }
}
