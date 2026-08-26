import Foundation
import XCTest
@testable import XmaxSDK

final class StorageManagerTests: XCTestCase {
    private let configuration = StorageConfiguration(
        bucket: "example-1250000000",
        region: "ap-shanghai",
        endpoint: "",
        credential: StorageCredential(
            accessKeyID: "access-key",
            secretAccessKey: "secret-key",
            sessionToken: "session-token"
        )
    )

    func testResolveObjectURLUsesUploadLocation() throws {
        let url = try StorageManager.resolveObjectURL(
            candidate: "//cdn.example.com/video/result.mp4",
            configuration: configuration,
            objectKey: "ignored.mp4"
        )

        XCTAssertEqual(url.absoluteString, "https://cdn.example.com/video/result.mp4")
    }

    func testResolveObjectURLBuildsDefaultEndpointAndEncodesKey() throws {
        let url = try StorageManager.resolveObjectURL(
            candidate: nil,
            configuration: configuration,
            objectKey: "video/示例 文件.mp4"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://example-1250000000.cos.ap-shanghai.myqcloud.com/" +
                "video/%E7%A4%BA%E4%BE%8B%20%E6%96%87%E4%BB%B6.mp4"
        )
    }

    func testResolveObjectURLAddsBucketToRegionalEndpoint() throws {
        let customConfiguration = StorageConfiguration(
            bucket: configuration.bucket,
            region: configuration.region,
            endpoint: "cos.ap-shanghai.myqcloud.com",
            credential: configuration.credential
        )

        let url = try StorageManager.resolveObjectURL(
            candidate: "",
            configuration: customConfiguration,
            objectKey: "images/input.png"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://example-1250000000.cos.ap-shanghai.myqcloud.com/images/input.png"
        )
    }

    func testResolveObjectURLEncodesReservedCharactersInObjectKey() throws {
        let url = try StorageManager.resolveObjectURL(
            candidate: nil,
            configuration: configuration,
            objectKey: "input/question?.png"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://example-1250000000.cos.ap-shanghai.myqcloud.com/" +
                "input/question%3F.png"
        )
    }

    func testUploadRejectsInvalidConfigurationBeforeStartingRequest() async {
        let invalidConfiguration = StorageConfiguration(
            bucket: "invalid bucket",
            region: configuration.region,
            endpoint: configuration.endpoint,
            credential: configuration.credential
        )

        do {
            _ = try await StorageManager().upload(
                source: .data(Data("value".utf8)),
                objectKey: "input.txt",
                contentType: "text/plain",
                configuration: invalidConfiguration
            )
            XCTFail("Expected upload validation to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .uploadError,
                    message: "Storage bucket is invalid"
                )
            )
        }
    }

    func testDownloadWritesDataAndReportsProgress() async throws {
        let payload = Data("downloaded-data".utf8)
        URLProtocolStub.setResponse(statusCode: 200, data: payload)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [URLProtocolStub.self]
        let manager = StorageManager(
            session: URLSession(configuration: sessionConfiguration)
        )
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let progress = StorageProgressRecorder()
        defer {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let result = try await manager.download(
            remoteURL: URL(string: "https://example.com/file")!,
            destinationURL: destinationURL,
            progress: progress.record
        )

        XCTAssertEqual(result.fileURL, destinationURL)
        XCTAssertEqual(result.byteCount, Int64(payload.count))
        XCTAssertEqual(try Data(contentsOf: destinationURL), payload)
        XCTAssertEqual(progress.value, [Int64(payload.count), Int64(payload.count)])
    }

    func testDownloadMapsHTTPFailure() async {
        URLProtocolStub.setResponse(statusCode: 403, data: Data())
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [URLProtocolStub.self]
        let manager = StorageManager(
            session: URLSession(configuration: sessionConfiguration)
        )
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            _ = try await manager.download(
                remoteURL: URL(string: "https://example.com/file")!,
                destinationURL: destinationURL,
                progress: nil
            )
            XCTFail("Expected download to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .downloadError,
                    message: "Storage download failed with HTTP 403",
                    httpStatus: 403
                )
            )
        }
    }
}

private final class StorageProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [Int64] = []

    var value: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }

    func record(completedBytes: Int64, totalBytes: Int64) {
        lock.lock()
        bytes = [completedBytes, totalBytes]
        lock.unlock()
    }
}

private final class URLProtocolStub: URLProtocol {
    private static let state = URLProtocolStubState()

    static func setResponse(statusCode: Int, data: Data) {
        state.setResponse(statusCode: statusCode, data: data)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let responseValue = Self.state.response
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseValue.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(responseValue.data.count)"]
        )!

        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: responseValue.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class URLProtocolStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var statusCode = 200
    private var data = Data()

    var response: (statusCode: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (statusCode, data)
    }

    func setResponse(statusCode: Int, data: Data) {
        lock.lock()
        self.statusCode = statusCode
        self.data = data
        lock.unlock()
    }
}
