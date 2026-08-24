import Foundation

/// SDK 向接入方暴露的统一错误码。
public enum XmaxErrorCode: String, CaseIterable, Sendable {

    case invalidAPIKey = "INVALID_API_KEY"
    case invalidConfiguration = "INVALID_CONFIGURATION"
    case internalError = "INTERNAL_ERROR"
    case networkError = "NETWORK_ERROR"
    case apiError = "API_ERROR"
    case sessionError = "SESSION_ERROR"
    case rtcError = "RTC_ERROR"
    case mediaError = "MEDIA_ERROR"
    case cameraPermissionDenied = "CAMERA_PERMISSION_DENIED"
    case microphonePermissionDenied = "MICROPHONE_PERMISSION_DENIED"
    case uploadError = "UPLOAD_ERROR"
    case downloadError = "DOWNLOAD_ERROR"
    case unsafeImage = "UNSAFE_IMAGE"
    case cancelled = "CANCELLED"
    case timeout = "TIMEOUT"
}

/// 表示 SDK 抛出或回调给接入方的统一错误。
public struct XmaxError: Error, LocalizedError, Equatable, Sendable {

    /// SDK 统一错误码。
    public let code: XmaxErrorCode

    /// 面向接入方的错误原因。
    public let message: String

    /// Xmax API 返回的业务错误码；非 API 业务错误时为空。
    public let apiCode: Int?

    /// HTTP 响应状态码；请求未获得响应时为空。
    public let httpStatus: Int?

    /// 创建 SDK 错误。
    ///
    /// - Parameters:
    ///   - code: SDK 统一错误码。
    ///   - message: 面向接入方的错误原因。
    ///   - apiCode: Xmax API 返回的可选业务错误码。
    ///   - httpStatus: 可选的 HTTP 响应状态码。
    public init(
        code: XmaxErrorCode,
        message: String,
        apiCode: Int? = nil,
        httpStatus: Int? = nil
    ) {
        self.code = code
        self.message = message
        self.apiCode = apiCode
        self.httpStatus = httpStatus
    }

    /// `LocalizedError` 使用的错误说明。
    public var errorDescription: String? {
        message
    }
}
