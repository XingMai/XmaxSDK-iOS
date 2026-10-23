//
//  ApiServicing.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An HTTP method supported by the Xmax API.
enum ApiMethod: String, Sendable {

    /// Reads a server resource.
    case get = "GET"

    /// Submits data or creates a resource.
    case post = "POST"

    /// Updates a server resource.
    case put = "PUT"

    /// Deletes a server resource.
    case delete = "DELETE"
}

/// An interface for Xmax API requests.
protocol ApiServicing: Sendable {

    /// Sends an HTTP request and decodes its response.
    ///
    /// - Parameters:
    ///   - method: The request's HTTP method.
    ///   - path: The path relative to the API root.
    ///   - body: The encoded body, or `nil` for no body.
    ///   - responseType: The response decoding type.
    ///
    /// - Returns: The decoded business response.
    ///
    /// - Throws: An error if credentials or URL are invalid, the request is rejected, or transport
    ///   or decoding fails.
    func request<Response: Decodable & Sendable>(
        _ method: ApiMethod,
        path: String,
        body: Data?,
        as responseType: Response.Type
    ) async throws -> Response
}

extension ApiServicing {

    /// Sends a GET request and decodes the response.
    ///
    /// - Parameters:
    ///   - path: The path relative to the API root.
    ///   - responseType: The response decoding type.
    ///
    /// - Returns: The decoded business response.
    ///
    /// - Throws: An error if the request, business response, or decoding fails.
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

    /// Sends a POST request and decodes the response.
    ///
    /// - Parameters:
    ///   - path: The path relative to the API root.
    ///   - responseType: The response decoding type.
    ///
    /// - Returns: The decoded business response.
    ///
    /// - Throws: An error if the request, business response, or decoding fails.
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

    /// Sends a POST request with a JSON body.
    ///
    /// - Parameters:
    ///   - path: The path relative to the API root.
    ///   - body: The request data to encode as JSON.
    ///   - responseType: The response decoding type.
    ///
    /// - Returns: The decoded business response.
    ///
    /// - Throws: An error if body encoding, transport, business response, or decoding fails.
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

    /// Sends a PUT request and decodes the response.
    ///
    /// - Parameters:
    ///   - path: The path relative to the API root.
    ///   - responseType: The response decoding type.
    ///
    /// - Returns: The decoded business response.
    ///
    /// - Throws: An error if the request, business response, or decoding fails.
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

    /// Sends a PUT request with a JSON body.
    ///
    /// - Parameters:
    ///   - path: The path relative to the API root.
    ///   - body: The request data to encode as JSON.
    ///   - responseType: The response decoding type.
    ///
    /// - Returns: The decoded business response.
    ///
    /// - Throws: An error if body encoding, transport, business response, or decoding fails.
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

    /// Sends a DELETE request and decodes the response.
    ///
    /// - Parameters:
    ///   - path: The path relative to the API root.
    ///   - responseType: The response decoding type.
    ///
    /// - Returns: The decoded business response.
    ///
    /// - Throws: An error if the request, business response, or decoding fails.
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

    /// Encodes request data as JSON.
    ///
    /// - Parameter body: The encodable request data.
    ///
    /// - Returns: The JSON HTTP body.
    ///
    /// - Throws: An API error if JSON encoding fails.
    private func encode<Body: Encodable & Sendable>(
        _ body: Body
    ) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw XmaxError(
                code: .apiError,
                message: "Failed to encode API request body: " + ErrorMessageFormatter.format(error)
            )
        }
    }
}
