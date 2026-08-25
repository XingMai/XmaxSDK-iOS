import Foundation

/// 负责发送 Xmax API 请求并统一处理响应、日志和错误。
final class ApiService: ApiServicing, Sendable {

    // API 配置
    static let defaultBaseURL = URL(string: "https://cloud.xmax.22duck.cn/open/api/v1")!
    static let defaultTimeoutInterval: TimeInterval = 15

    // 平台资源
    private let apiKey: String
    private let baseURL: URL
    private let timeoutInterval: TimeInterval
    private let session: URLSession

    /// 创建 API Service。
    init(
        apiKey: String,
        baseURL: URL = ApiService.defaultBaseURL,
        timeoutInterval: TimeInterval = ApiService.defaultTimeoutInterval,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.session = session
    }

    func request<Response: Decodable & Sendable>(
        _ method: ApiMethod,
        path: String,
        body: Data?,
        as responseType: Response.Type
    ) async throws -> Response {
        try validateConfiguration()
        let request = try makeRequest(
            method: method,
            path: path,
            body: body
        )
        let startedAt = DispatchTime.now().uptimeNanoseconds

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
        } catch {
            let durationMs = Self.durationMs(since: startedAt)
            ApiLogger.logFailure(
                method: method,
                path: path,
                error: error,
                durationMs: durationMs
            )
            throw Self.transportError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let error = XmaxError(
                code: .networkError,
                message: "HTTP request returned a non-HTTP response"
            )
            ApiLogger.logFailure(
                method: method,
                path: path,
                error: error,
                durationMs: Self.durationMs(since: startedAt)
            )
            throw error
        }

        do {
            let value: Response = try Self.parseResponse(
                data,
                statusCode: httpResponse.statusCode,
                as: responseType
            )
            ApiLogger.logResponse(
                method: method,
                path: path,
                statusCode: httpResponse.statusCode,
                bodyByteCount: data.count,
                durationMs: Self.durationMs(since: startedAt),
                successful: true
            )
            return value
        } catch {
            ApiLogger.logResponse(
                method: method,
                path: path,
                statusCode: httpResponse.statusCode,
                bodyByteCount: data.count,
                durationMs: Self.durationMs(since: startedAt),
                successful: false
            )
            if let xmaxError = error as? XmaxError {
                throw xmaxError
            }
            throw XmaxError(
                code: .apiError,
                message: ErrorMessageFormatter.format(error),
                httpStatus: httpResponse.statusCode
            )
        }
    }
}

private extension ApiService {

    /// 表示 Xmax API 统一响应中的公共元数据。
    struct EnvelopeMetadata: Decodable {
        let success: Bool?
        let code: Int?
        let message: String?
    }

    /// 表示 Xmax API 成功响应中的业务数据。
    struct PayloadEnvelope<Response: Decodable>: Decodable {
        let data: Response?
    }

    func validateConfiguration() throws {
        guard !apiKey.isEmpty else {
            throw XmaxError(
                code: .invalidAPIKey,
                message: "API key cannot be empty"
            )
        }
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil,
              timeoutInterval > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "API service configuration is invalid"
            )
        }
    }

    func makeRequest(
        method: ApiMethod,
        path: String,
        body: Data?
    ) throws -> URLRequest {
        let normalizedPath = path.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedPath.isEmpty,
              !normalizedPath.contains("://"),
              !normalizedPath.hasPrefix("//") else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "API request path is invalid"
            )
        }

        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        let relativePath = normalizedPath.hasPrefix("/")
            ? normalizedPath
            : "/\(normalizedPath)"
        guard let url = URL(string: base + relativePath),
              url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              url.host?.lowercased() == baseURL.host?.lowercased() else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "API request path is invalid"
            )
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        return request
    }

    static func parseResponse<Response: Decodable>(
        _ data: Data,
        statusCode: Int,
        as _: Response.Type
    ) throws -> Response {
        let metadata: EnvelopeMetadata
        do {
            metadata = try JSONDecoder().decode(
                EnvelopeMetadata.self,
                from: data
            )
        } catch {
            throw XmaxError(
                code: .apiError,
                message: "Server returned invalid JSON",
                httpStatus: statusCode
            )
        }

        guard (200..<300).contains(statusCode),
              metadata.success == true else {
            let message = metadata.message?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedMessage: String
            if let message, !message.isEmpty {
                resolvedMessage = message
            } else {
                resolvedMessage = "Xmax API request failed"
            }
            throw XmaxError(
                code: .apiError,
                message: resolvedMessage,
                apiCode: metadata.code,
                httpStatus: statusCode
            )
        }

        do {
            let envelope = try JSONDecoder().decode(
                PayloadEnvelope<Response>.self,
                from: data
            )
            guard let value = envelope.data else {
                throw DecodingError.valueNotFound(
                    Response.self,
                    .init(
                        codingPath: [],
                        debugDescription: "API response data is missing"
                    )
                )
            }
            return value
        } catch {
            throw XmaxError(
                code: .apiError,
                message: "Server returned invalid response data",
                httpStatus: statusCode
            )
        }
    }

    static func transportError(_ error: any Error) -> XmaxError {
        if error is CancellationError {
            return XmaxError(
                code: .cancelled,
                message: "API request was cancelled"
            )
        }

        let platformError = error as NSError
        if platformError.domain == NSURLErrorDomain,
           platformError.code == NSURLErrorCancelled {
            return XmaxError(
                code: .cancelled,
                message: "API request was cancelled"
            )
        }

        return XmaxError(
            code: .networkError,
            message: "HTTP request failed: " +
                ErrorMessageFormatter.format(error)
        )
    }

    static func durationMs(since startedAt: UInt64) -> Int {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds
            - startedAt
        return Int(elapsedNanoseconds / 1_000_000)
    }
}
