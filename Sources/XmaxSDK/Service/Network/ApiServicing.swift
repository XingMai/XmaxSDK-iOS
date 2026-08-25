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

    /// 发送请求并将统一响应中的数据解析为指定类型。
    func request<Response: Decodable & Sendable>(
        _ method: ApiMethod,
        path: String,
        body: Data?,
        as responseType: Response.Type
    ) async throws -> Response
}

extension ApiServicing {

    /// 发送 GET 请求。
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

    /// 发送不带请求体的 POST 请求。
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

    /// 发送不带请求体的 PUT 请求。
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

    /// 发送 DELETE 请求。
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
