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
