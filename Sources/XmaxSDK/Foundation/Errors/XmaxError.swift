import Foundation

/// SDK 内部组件上报统一错误时使用的监听器。
typealias XmaxErrorListener = @Sendable (XmaxError) -> Void

/// SDK 向接入方暴露的统一错误码。
public enum XmaxErrorCode: String, CaseIterable, Sendable {

    /// API Key 未配置或为空。
    case invalidAPIKey = "INVALID_API_KEY"

    /// 调用参数、配置或当前生命周期状态不符合操作要求。
    case invalidConfiguration = "INVALID_CONFIGURATION"

    /// SDK 内部发生无法归类的非预期错误。
    case internalError = "INTERNAL_ERROR"

    /// 网络不可用、连接失败或 HTTP 请求无法完成。
    case networkError = "NETWORK_ERROR"

    /// Xmax API 返回业务失败，或者响应数据无法正确解析。
    case apiError = "API_ERROR"

    /// 实时生成会话数据缺失、会话关闭或心跳状态异常。
    case sessionError = "SESSION_ERROR"

    /// RTC Engine、房间、媒体传输或渲染绑定发生错误。
    case rtcError = "RTC_ERROR"

    /// 本地媒体读取、解码、同步或帧处理发生错误。
    case mediaError = "MEDIA_ERROR"

    /// 当前系统、设备或视频规格不支持远端视频插帧。
    case frameInterpolationUnsupported =
        "FRAME_INTERPOLATION_UNSUPPORTED"

    /// 接入方未授予相机权限。
    case cameraPermissionDenied = "CAMERA_PERMISSION_DENIED"

    /// 接入方未授予麦克风权限。
    case microphonePermissionDenied = "MICROPHONE_PERMISSION_DENIED"

    /// 文件或二进制数据上传失败。
    case uploadError = "UPLOAD_ERROR"

    /// 远端文件下载失败。
    case downloadError = "DOWNLOAD_ERROR"

    /// 图片未通过内容安全检查。
    case unsafeImage = "UNSAFE_IMAGE"

    /// 操作因生命周期切换或接入方主动终止而正常取消。
    case cancelled = "CANCELLED"

    /// 等待连接、房间事件或生成结果超过规定时间。
    case timeout = "TIMEOUT"
}

/// 描述 SDK 错误对当前操作或实时生命周期的影响程度。
public enum XmaxErrorSeverity: String, CaseIterable, Sendable {

    /// 当前操作未完成，但 SDK 仍可继续使用或维持现有实时流程。
    case recoverable = "RECOVERABLE"

    /// 当前实时流程无法继续，需要接入方感知并进行恢复或退出处理。
    case fatal = "FATAL"
}

/// 表示 SDK 抛出或回调给接入方的统一错误。
public struct XmaxError: Error, LocalizedError, Equatable, Sendable {

    /// SDK 统一错误码。
    public let code: XmaxErrorCode

    /// 面向接入方的可读错误说明。
    public let message: String

    /// 错误对当前操作或实时生命周期的影响程度。
    public let severity: XmaxErrorSeverity

    /// Xmax API 返回的业务错误码；非 API 业务错误时为空。
    public let apiCode: Int?

    /// HTTP 响应状态码；请求未获得响应时为空。
    public let httpStatus: Int?

    /// 创建 SDK 错误。
    ///
    /// - Parameters:
    ///   - code: SDK 统一错误码。
    ///   - message: 面向接入方的可读错误说明。
    ///   - severity: 错误影响程度；省略时根据 `code` 提供默认值。
    ///   - apiCode: Xmax API 返回的可选业务错误码。
    ///   - httpStatus: 可选的 HTTP 响应状态码。
    public init(
        code: XmaxErrorCode,
        message: String,
        severity: XmaxErrorSeverity? = nil,
        apiCode: Int? = nil,
        httpStatus: Int? = nil
    ) {
        self.code = code
        self.message = message
        self.severity = severity ?? Self.defaultSeverity(for: code)
        self.apiCode = apiCode
        self.httpStatus = httpStatus
    }

    /// `LocalizedError` 使用的错误说明。
    public var errorDescription: String? {
        message
    }

    /// 将未知错误转换为 SDK 内部错误，已有 `XmaxError` 原样返回。
    ///
    /// - Parameter error: 待转换的错误。
    /// - Returns: 可向接入方抛出或回调的统一错误。
    public static func from(_ error: any Error) -> XmaxError {
        if let xmaxError = error as? XmaxError {
            return xmaxError
        }

        let description = (error as NSError).localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = description.isEmpty ? String(describing: error) : description

        return XmaxError(
            code: .internalError,
            message: message
        )
    }
}

extension XmaxError {
    /// 保留原错误信息并更新影响程度。
    func withSeverity(_ severity: XmaxErrorSeverity) -> XmaxError {
        XmaxError(
            code: code,
            message: message,
            severity: severity,
            apiCode: apiCode,
            httpStatus: httpStatus
        )
    }
}

private extension XmaxError {
    static func defaultSeverity(
        for code: XmaxErrorCode
    ) -> XmaxErrorSeverity {
        switch code {
        case .invalidAPIKey,
             .invalidConfiguration,
             .frameInterpolationUnsupported,
             .cameraPermissionDenied,
             .microphonePermissionDenied,
             .cancelled:
            .recoverable
        case .internalError,
             .networkError,
             .apiError,
             .sessionError,
             .rtcError,
             .mediaError,
             .uploadError,
             .downloadError,
             .unsafeImage,
             .timeout:
            .fatal
        }
    }
}
