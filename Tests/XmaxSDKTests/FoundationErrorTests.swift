import Foundation
import XCTest
@testable import XmaxSDK

final class FoundationErrorTests: XCTestCase {
    func testFromKeepsExistingXmaxError() {
        let expected = XmaxError(
            code: .networkError,
            message: "Connection failed"
        )

        XCTAssertEqual(XmaxError.from(expected), expected)
    }

    func testFromWrapsPlatformError() {
        let platformError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "Request timed out"]
        )

        XCTAssertEqual(
            XmaxError.from(platformError),
            XmaxError(
                code: .internalError,
                message: "Request timed out"
            )
        )
    }

    func testDefaultSeverityUsesErrorCode() {
        let recoverableError = XmaxError(
            code: .invalidConfiguration,
            message: "Invalid state"
        )
        let fatalError = XmaxError(
            code: .rtcError,
            message: "RTC failed"
        )

        XCTAssertEqual(recoverableError.severity, .recoverable)
        XCTAssertEqual(fatalError.severity, .fatal)
    }

    func testUpdatingSeverityPreservesOriginalErrorDetails() {
        let error = XmaxError(
            code: .rtcError,
            message: "send failed",
            apiCode: 1003,
            httpStatus: 500
        ).withSeverity(.recoverable)

        XCTAssertEqual(error.code, .rtcError)
        XCTAssertEqual(error.message, "send failed")
        XCTAssertEqual(error.severity, .recoverable)
        XCTAssertEqual(error.apiCode, 1003)
        XCTAssertEqual(error.httpStatus, 500)
    }

    @MainActor
    func testRealtimeErrorHandlerOnlyNotifiesFatalErrors() async {
        let handler = RealtimeErrorHandler()
        var receivedErrors: [XmaxError] = []
        handler.setListener { error in
            receivedErrors.append(error)
        }
        let recoverableError = XmaxError(
            code: .rtcError,
            message: "Stop signal failed",
            severity: .recoverable
        )
        let fatalError = XmaxError(
            code: .rtcError,
            message: "RTC connection failed",
            severity: .fatal
        )

        await handler.report(recoverableError)
        await handler.report(fatalError)

        XCTAssertEqual(receivedErrors, [fatalError])
    }

    func testFormatterIncludesXmaxErrorDetails() {
        let error = XmaxError(
            code: .apiError,
            message: "Request rejected",
            apiCode: 1003,
            httpStatus: 400
        )

        XCTAssertEqual(
            ErrorMessageFormatter.format(error),
            "Request rejected（API_ERROR，业务码 1003，HTTP 400）"
        )
    }

    func testFormatterIncludesPlatformErrorCode() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "Network unavailable"]
        )

        XCTAssertEqual(
            ErrorMessageFormatter.format(error),
            "Network unavailable（平台错误码：-1009）"
        )
    }
}
