//
//  ApiService.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 负责发送 Xmax API 请求并统一处理响应、日志和错误。
final class ApiService: ApiServicing, Sendable {

    // API 配置
    static let defaultTimeoutInterval: TimeInterval = 15

    // 请求配置
    private let apiKey: String
    private let baseURL: URL
    private let timeoutInterval: TimeInterval

    // 网络资源
    private let session: URLSession

    /// 创建使用指定地址、认证信息与网络会话的 API 服务。
    ///
    /// - Parameters:
    ///   - apiKey: 访问 API 的凭证，保存前去除首尾空白。
    ///   - baseURL: 服务端 API 根地址，必须使用 HTTPS。
    ///   - timeoutInterval: 单次请求的超时时间，单位为秒。
    ///   - session: 实际发送网络请求的会话。
    init(
        apiKey: String,
        baseURL: URL,
        timeoutInterval: TimeInterval = ApiService.defaultTimeoutInterval,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.session = session
    }

    /// 发送 HTTP 请求并将响应数据解析为指定类型。
    ///
    /// - Parameters:
    ///   - method: 请求使用的 HTTP 方法。
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - body: 已编码的请求体；`nil` 表示无请求体。
    ///   - responseType: 响应数据需要解码为的类型。
    /// - Returns: 从 API 响应中解析出的业务数据。
    /// - Throws: 凭证或地址无效、请求失败、服务端返回错误或响应解析失败时抛出错误。
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
                successful: false,
                responseBody: data
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

        // 响应状态
        let success: Bool?
        let code: Int?
        let message: String?
    }

    /// 表示 Xmax API 成功响应中的业务数据。
    struct PayloadEnvelope<Response: Decodable>: Decodable {

        // 业务数据
        let data: Response?
    }

    /// 确认请求凭证、HTTPS 根地址和超时时间有效。
    ///
    /// - Throws: API Key 为空或网络配置无效时抛出错误。
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

    /// 组合相对路径并构建带认证与运行环境信息的 HTTP 请求。
    ///
    /// - Parameters:
    ///   - method: 请求的 HTTP 方法。
    ///   - path: 相对 API 根地址的路径，不允许指定其他主机。
    ///   - body: 已编码的请求体；`nil` 表示无请求体。
    /// - Returns: 配置超时、请求头和正文后的 HTTP 请求。
    /// - Throws: 路径为空、不合法或指向其他主机时抛出配置错误。
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
        let runtime = RuntimeInfo.current
        request.setValue(runtime.platform, forHTTPHeaderField: "X-Platform")
        request.setValue(runtime.osVersion, forHTTPHeaderField: "X-OS-Version")
        request.setValue(runtime.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue(runtime.deviceModel, forHTTPHeaderField: "X-Device-Model")
        return request
    }

    /// 检查 HTTP 和业务状态，并解析统一响应中的数据字段。
    ///
    /// - Parameters:
    ///   - data: 服务端响应正文。
    ///   - statusCode: HTTP 响应状态码。
    ///   - as: 业务数据的目标解码类型。
    /// - Returns: 解析完成的业务数据。
    /// - Throws: 响应不是有效 JSON、请求未成功或数据缺失及类型不匹配时抛出 API 错误。
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

    /// 将网络层错误转换为 SDK 的取消或网络错误。
    ///
    /// - Parameter error: 网络请求产生的原始错误。
    /// - Returns: 保留取消语义的 SDK 错误。
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

    /// 计算从指定单调时钟时间到现在的耗时。
    ///
    /// - Parameter startedAt: 请求开始时的系统运行时间，单位为纳秒。
    /// - Returns: 已过去的整数毫秒数。
    static func durationMs(since startedAt: UInt64) -> Int {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds
            - startedAt
        return Int(elapsedNanoseconds / 1_000_000)
    }
}
