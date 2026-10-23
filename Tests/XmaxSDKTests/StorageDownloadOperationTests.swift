//
//  StorageDownloadOperationTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import XCTest
@testable import XmaxSDK

final class StorageDownloadOperationTests: XCTestCase {
    func testDownloadReportsProgressBeforeReplacingExistingFile() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("video.mp4")
        let original = Data("previous-video".utf8)
        try original.write(to: destination)
        let intermediate = expectation(description: "incremental download progress")
        intermediate.assertForOverFulfill = false
        let progress = DownloadProgressRecorder()

        let result = try await StorageDownloadOperation { completed, total in
            progress.record(completed: completed, total: total)
            if completed > 0, completed < total {
                XCTAssertEqual(try? Data(contentsOf: destination), original)
                intermediate.fulfill()
            }
        }.value(session: session, remoteURL: remoteURL("success"), destinationURL: destination)

        await fulfillment(of: [intermediate], timeout: 2)
        XCTAssertEqual(result, DownloadedFile(fileURL: destination, byteCount: Int64(DownloadProtocolStub.byteCount)))
        XCTAssertEqual(try Data(contentsOf: destination), DownloadProtocolStub.expectedData())
        XCTAssertEqual(progress.events.last?.completed, result.byteCount)
        XCTAssertEqual(progress.events.last?.total, result.byteCount)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["video.mp4"])
    }

    func testUnknownContentLengthIsResolvedAtCompletion() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = DownloadProgressRecorder()
        let result = try await StorageDownloadOperation(progress: progress.record).value(
            session: session,
            remoteURL: remoteURL("unknown"),
            destinationURL: directory.appendingPathComponent("video.mp4")
        )

        XCTAssertTrue(progress.events.contains { $0.completed > 0 && $0.total == 0 })
        XCTAssertEqual(progress.events.last?.completed, result.byteCount)
        XCTAssertEqual(progress.events.last?.total, result.byteCount)
    }

    func testHTTPFailurePreservesExistingFileAndDoesNotReportSuccess() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("video.mp4")
        let original = Data("previous-video".utf8)
        try original.write(to: destination)
        let progress = DownloadProgressRecorder()

        do {
            _ = try await StorageDownloadOperation(progress: progress.record).value(
                session: session,
                remoteURL: remoteURL("forbidden"),
                destinationURL: destination
            )
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.httpStatus, 403)
            XCTAssertEqual((error as? XmaxError)?.code, .downloadError)
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertTrue(progress.events.isEmpty)
    }

    func testInterruptedTransferPreservesExistingFile() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("video.mp4")
        let original = Data("previous-video".utf8)
        try original.write(to: destination)

        do {
            _ = try await StorageDownloadOperation(progress: nil).value(
                session: session,
                remoteURL: remoteURL("interrupted"),
                destinationURL: destination
            )
            XCTFail("Expected transfer failure")
        } catch {
            XCTAssertEqual((error as NSError).code, NSURLErrorNetworkConnectionLost)
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["video.mp4"])
    }

    func testCancellationStopsDownloadAndPreservesExistingFile() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("video.mp4")
        let original = Data("previous-video".utf8)
        try original.write(to: destination)
        let received = expectation(description: "download started")
        received.assertForOverFulfill = false
        let progress = DownloadProgressRecorder()
        let url = remoteURL("cancel")
        let task = Task {
            try await StorageDownloadOperation { completed, total in
                progress.record(completed: completed, total: total)
                if completed > 0, completed < total { received.fulfill() }
            }.value(session: session, remoteURL: url, destinationURL: destination)
        }

        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as NSError).code == NSURLErrorCancelled)
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertFalse(progress.events.contains { $0.completed == $0.total && $0.total > 0 })
    }

    func testEmptyFileIsSavedWithoutProgressDivision() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = DownloadProgressRecorder()
        let result = try await StorageDownloadOperation(progress: progress.record).value(
            session: session,
            remoteURL: remoteURL("empty"),
            destinationURL: directory.appendingPathComponent("empty.mp4")
        )
        XCTAssertEqual(result.byteCount, 0)
        XCTAssertEqual(try Data(contentsOf: result.fileURL), Data())
        XCTAssertEqual(progress.events.last?.completed, 0)
        XCTAssertEqual(progress.events.last?.total, 0)
    }

    func testDirectoryDestinationIsNotReplaced() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: existing)

        do {
            _ = try await StorageDownloadOperation(progress: nil).value(
                session: session,
                remoteURL: remoteURL("success"),
                destinationURL: directory
            )
            XCTFail("Expected directory destination rejection")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .downloadError)
        }
        XCTAssertEqual(try Data(contentsOf: existing), Data("keep".utf8))
    }

    func testConcurrentDownloadsKeepFilesAndProgressSeparate() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstProgress = DownloadProgressRecorder()
        let secondProgress = DownloadProgressRecorder()
        let firstURL = remoteURL("success")
        let secondURL = remoteURL("second")
        async let first = StorageDownloadOperation(progress: firstProgress.record).value(
            session: session,
            remoteURL: firstURL,
            destinationURL: directory.appendingPathComponent("first.mp4")
        )
        async let second = StorageDownloadOperation(progress: secondProgress.record).value(
            session: session,
            remoteURL: secondURL,
            destinationURL: directory.appendingPathComponent("second.mp4")
        )
        let results = try await (first, second)
        XCTAssertEqual(try Data(contentsOf: results.0.fileURL), DownloadProtocolStub.expectedData())
        XCTAssertEqual(try Data(contentsOf: results.1.fileURL), DownloadProtocolStub.expectedData(byte: 2))
        XCTAssertEqual(firstProgress.events.last?.completed, results.0.byteCount)
        XCTAssertEqual(secondProgress.events.last?.completed, results.1.byteCount)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func remoteURL(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}

private final class DownloadProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [(completed: Int64, total: Int64)] = []

    var events: [(completed: Int64, total: Int64)] {
        lock.withLock { storedEvents }
    }

    func record(completed: Int64, total: Int64) {
        lock.withLock { storedEvents.append((completed, total)) }
    }
}

private final class DownloadProtocolStub: URLProtocol {
    static let byteCount = 512 * 1024
    private let deliveryQueue = DispatchQueue(label: "xmax.storage.download-test")
    private var cancelled = false

    static func expectedData(byte: UInt8 = 1) -> Data {
        Data(repeating: byte, count: byteCount)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        deliveryQueue.async(execute: DispatchWorkItem { self.sendResponse() })
    }

    override func stopLoading() {
        deliveryQueue.async(execute: DispatchWorkItem { self.cancelled = true })
    }

    private func sendResponse() {
        guard !cancelled else { return }
        let path = request.url!.lastPathComponent
        let length = path == "empty" ? 0 : Self.byteCount
        let headers = path == "unknown" ? [:] : ["Content-Length": String(length)]
        let response = HTTPURLResponse(
            url: request.url!, statusCode: path == "forbidden" ? 403 : 200,
            httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        sendChunk(offset: 0, length: length, path: path)
    }

    private func sendChunk(offset: Int, length: Int, path: String) {
        guard !cancelled else { return }
        guard offset < length else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if path == "interrupted", offset > 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let count = min(64 * 1024, length - offset)
        client?.urlProtocol(self, didLoad: Data(repeating: path == "second" ? 2 : 1, count: count))
        deliveryQueue.asyncAfter(
            deadline: .now() + (path == "cancel" ? 0.2 : 0.04),
            execute: DispatchWorkItem {
                self.sendChunk(offset: offset + count, length: length, path: path)
            }
        )
    }
}
