import Foundation

/// 表示视频帧中的一个像素数据平面。
struct VideoFramePlane: Equatable, Sendable {
    let data: Data
    let stride: Int
    let byteOffset: Int
    let byteLength: Int

    init(
        data: Data,
        stride: Int,
        byteOffset: Int = 0,
        byteLength: Int? = nil
    ) throws {
        guard !data.isEmpty,
              byteOffset >= 0,
              byteOffset < data.count else {
            throw Self.invalidRangeError
        }

        let resolvedByteLength = byteLength ?? data.count - byteOffset
        guard resolvedByteLength > 0,
              resolvedByteLength <= data.count - byteOffset else {
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

    private static var invalidRangeError: XmaxError {
        XmaxError(
            code: .invalidConfiguration,
            message: "Video frame plane range is invalid"
        )
    }
}
