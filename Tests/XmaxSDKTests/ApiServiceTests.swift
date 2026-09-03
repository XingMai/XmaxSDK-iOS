import Foundation
import XCTest
@testable import XmaxSDK

final class ApiServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ApiURLProtocolStub.reset()
    }

    func testGetBuildsAuthenticatedRequestAndDecodesEnvelope() async throws {
        ApiURLProtocolStub.setResponse(
            statusCode: 200,
            data: Data(
                #"{"success":true,"data":{"identifier":"value"}}"#.utf8
            )
        )
        let service = makeService(apiKey: "  test-api-key  ")

        let value = try await service.get(
            "/resource?kind=test",
            as: ApiTestResponse.self
        )

        XCTAssertEqual(value, ApiTestResponse(identifier: "value"))
        let request = try XCTUnwrap(ApiURLProtocolStub.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.example.com/v1/resource?kind=test"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Api-Key"),
            "test-api-key"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            "application/json"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Platform"),
            RuntimeInfo.current.platform
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-OS-Version"),
            RuntimeInfo.current.osVersion
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-SDK-Version"),
            RuntimeInfo.current.sdkVersion
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Device-Model"),
            RuntimeInfo.current.deviceModel
        )
        XCTAssertNil(request.httpBody)
    }

    func testPostEncodesJSONBody() async throws {
        ApiURLProtocolStub.setResponse(
            statusCode: 201,
            data: Data(
                #"{"success":true,"data":{"identifier":"created"}}"#.utf8
            )
        )
        let service = makeService()

        let value = try await service.post(
            "/resource",
            body: ApiTestBody(name: "示例"),
            as: ApiTestResponse.self
        )

        XCTAssertEqual(value.identifier, "created")
        let request = try XCTUnwrap(ApiURLProtocolStub.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        let requestBody = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(
            try JSONDecoder().decode(ApiTestBody.self, from: requestBody),
            ApiTestBody(name: "示例")
        )
    }

    func testBusinessFailurePreservesBusinessAndHTTPCodes() async {
        ApiURLProtocolStub.setResponse(
            statusCode: 403,
            data: Data(
                #"{"success":false,"code":1007,"message":"Access denied","data":{"unexpected":true}}"#.utf8
            )
        )
        let service = makeService()

        do {
            _ = try await service.get(
                "/resource",
                as: ApiTestResponse.self
            )
            XCTFail("Expected the API request to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .apiError,
                    message: "Access denied",
                    apiCode: 1007,
                    httpStatus: 403
                )
            )
        }
    }

    func testInvalidSuccessPayloadMapsToAPIError() async {
        ApiURLProtocolStub.setResponse(
            statusCode: 200,
            data: Data(
                #"{"success":true,"data":{"unexpected":true}}"#.utf8
            )
        )
        let service = makeService()

        do {
            _ = try await service.get(
                "/resource",
                as: ApiTestResponse.self
            )
            XCTFail("Expected invalid response data to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .apiError,
                    message: "Server returned invalid response data",
                    httpStatus: 200
                )
            )
        }
    }

    func testInvalidJSONMapsToAPIError() async {
        ApiURLProtocolStub.setResponse(
            statusCode: 502,
            data: Data("not-json".utf8)
        )
        let service = makeService()

        do {
            _ = try await service.get(
                "/resource",
                as: ApiTestResponse.self
            )
            XCTFail("Expected invalid JSON to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .apiError,
                    message: "Server returned invalid JSON",
                    httpStatus: 502
                )
            )
        }
    }

    func testTransportFailureMapsToNetworkError() async {
        ApiURLProtocolStub.setError(URLError(.notConnectedToInternet))
        let service = makeService()

        do {
            _ = try await service.get(
                "/resource",
                as: ApiTestResponse.self
            )
            XCTFail("Expected the transport request to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .networkError)
            XCTAssertTrue(
                (error as? XmaxError)?.message.hasPrefix(
                    "HTTP request failed:"
                ) == true
            )
        }
    }

    func testCancelledTransportMapsToCancelledError() async {
        ApiURLProtocolStub.setError(URLError(.cancelled))
        let service = makeService()

        do {
            _ = try await service.get(
                "/resource",
                as: ApiTestResponse.self
            )
            XCTFail("Expected the request to be cancelled")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .cancelled,
                    message: "API request was cancelled"
                )
            )
        }
    }

    func testEmptyAPIKeyFailsBeforeStartingRequest() async {
        let service = makeService(apiKey: " \n ")

        do {
            _ = try await service.get(
                "/resource",
                as: ApiTestResponse.self
            )
            XCTFail("Expected API key validation to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidAPIKey,
                    message: "API key cannot be empty"
                )
            )
            XCTAssertNil(ApiURLProtocolStub.request)
        }
    }

    func testRequestRejectsAbsolutePath() async {
        let service = makeService()

        do {
            _ = try await service.get(
                "https://other.example.com/resource",
                as: ApiTestResponse.self
            )
            XCTFail("Expected an absolute URL to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "API request path is invalid"
                )
            )
        }
    }

    func testResponseLogDoesNotContainResponseBody() {
        let message = ApiLogger.responseMessage(
            method: .post,
            path: "/session",
            statusCode: 400,
            bodyByteCount: 128,
            durationMs: 20
        )

        XCTAssertFalse(message.contains("room_token"))
        XCTAssertEqual(
            message,
            "POST /session\n" +
                "├─ 状态：400\n" +
                "├─ 耗时：20 ms\n" +
                "└─ 响应：128 bytes"
        )
    }

    private func makeService(
        apiKey: String = "test-api-key"
    ) -> ApiService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ApiURLProtocolStub.self]
        return ApiService(
            apiKey: apiKey,
            baseURL: URL(string: "https://api.example.com/v1")!,
            session: URLSession(configuration: configuration)
        )
    }
}

private struct ApiTestResponse: Codable, Equatable, Sendable {
    let identifier: String
}

private struct ApiTestBody: Codable, Equatable, Sendable {
    let name: String
}

private final class ApiURLProtocolStub: URLProtocol {

    // 共享状态
    private static let state = ApiURLProtocolStubState()

    static var request: URLRequest? {
        state.request
    }

    static func setResponse(statusCode: Int, data: Data) {
        state.setResponse(statusCode: statusCode, data: data)
    }

    static func setError(_ error: any Error) {
        state.setError(error)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = Self.state.start(request: request)
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(response.data.count)"]
        )!
        client?.urlProtocol(
            self,
            didReceive: httpResponse,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ApiURLProtocolStubState: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 响应配置
    private var statusCode = 200
    private var data = Data()
    private var error: (any Error)?

    // 运行状态
    private var capturedRequest: URLRequest?

    var request: URLRequest? {
        lock.withLock { capturedRequest }
    }

    func setResponse(statusCode: Int, data: Data) {
        lock.withLock {
            self.statusCode = statusCode
            self.data = data
            error = nil
        }
    }

    func setError(_ error: any Error) {
        lock.withLock {
            self.error = error
        }
    }

    func reset() {
        lock.withLock {
            statusCode = 200
            data = Data()
            error = nil
            capturedRequest = nil
        }
    }

    func start(request: URLRequest) -> ApiURLProtocolResponse {
        lock.withLock {
            capturedRequest = request
            return ApiURLProtocolResponse(
                statusCode: statusCode,
                data: data,
                error: error
            )
        }
    }
}

private struct ApiURLProtocolResponse {
    let statusCode: Int
    let data: Data
    let error: (any Error)?
}
