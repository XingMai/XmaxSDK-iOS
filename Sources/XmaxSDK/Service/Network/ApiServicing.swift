//
//  ApiServicing.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Xmax API 支持的 HTTP 请求方法。
enum ApiMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// 定义 Xmax API 的基础请求能力。
protocol ApiServicing: Sendable {

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
    ) async throws -> Response
}

extension ApiServicing {

    /// 发送 GET 请求并解析响应数据。
    ///
    /// - Parameters:
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - responseType: 响应数据需要解码为的类型。
    /// - Returns: 从 API 响应中解析出的业务数据。
    /// - Throws: 请求失败、服务端返回错误或响应解析失败时抛出错误。
    func get<Response: Decodable & Sendable>(
        _ path: String,
        as responseType: Response.Type
    ) async throws -> Response {
        try await request(
            .get,
            path: path,
            body: nil,
            as: responseType
        )
    }

    /// 发送 POST 请求并解析响应数据。
    ///
    /// - Parameters:
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - responseType: 响应数据需要解码为的类型。
    /// - Returns: 从 API 响应中解析出的业务数据。
    /// - Throws: 请求失败、服务端返回错误或响应解析失败时抛出错误。
    func post<Response: Decodable & Sendable>(
        _ path: String,
        as responseType: Response.Type
    ) async throws -> Response {
        try await request(
            .post,
            path: path,
            body: nil,
            as: responseType
        )
    }

    /// 发送带 JSON 请求体的 POST 请求。
    ///
    /// - Parameters:
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - body: 需要编码为 JSON 的请求数据。
    ///   - responseType: 响应数据需要解码为的类型。
    /// - Returns: 从 API 响应中解析出的业务数据。
    /// - Throws: 请求体编码失败、请求失败、服务端返回错误或响应解析失败时抛出错误。
    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        as responseType: Response.Type
    ) async throws -> Response {
        try await request(
            .post,
            path: path,
            body: try encode(body),
            as: responseType
        )
    }

    /// 发送 PUT 请求并解析响应数据。
    ///
    /// - Parameters:
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - responseType: 响应数据需要解码为的类型。
    /// - Returns: 从 API 响应中解析出的业务数据。
    /// - Throws: 请求失败、服务端返回错误或响应解析失败时抛出错误。
    func put<Response: Decodable & Sendable>(
        _ path: String,
        as responseType: Response.Type
    ) async throws -> Response {
        try await request(
            .put,
            path: path,
            body: nil,
            as: responseType
        )
    }

    /// 发送带 JSON 请求体的 PUT 请求。
    ///
    /// - Parameters:
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - body: 需要编码为 JSON 的请求数据。
    ///   - responseType: 响应数据需要解码为的类型。
    /// - Returns: 从 API 响应中解析出的业务数据。
    /// - Throws: 请求体编码失败、请求失败、服务端返回错误或响应解析失败时抛出错误。
    func put<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        as responseType: Response.Type
    ) async throws -> Response {
        try await request(
            .put,
            path: path,
            body: try encode(body),
            as: responseType
        )
    }

    /// 发送 DELETE 请求并解析响应数据。
    ///
    /// - Parameters:
    ///   - path: 相对于 API 根地址的请求路径。
    ///   - responseType: 响应数据需要解码为的类型。
    /// - Returns: 从 API 响应中解析出的业务数据。
    /// - Throws: 请求失败、服务端返回错误或响应解析失败时抛出错误。
    func delete<Response: Decodable & Sendable>(
        _ path: String,
        as responseType: Response.Type
    ) async throws -> Response {
        try await request(
            .delete,
            path: path,
            body: nil,
            as: responseType
        )
    }

    /// 将请求数据编码为 JSON。
    ///
    /// - Parameter body: 符合编码协议的请求数据。
    /// - Returns: 可用于 HTTP 请求体的 JSON 数据。
    /// - Throws: JSON 编码失败时抛出 API 错误。
    private func encode<Body: Encodable & Sendable>(
        _ body: Body
    ) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw XmaxError(
                code: .apiError,
                message: "Failed to encode API request body: " +
                    ErrorMessageFormatter.format(error)
            )
        }
    }
}
