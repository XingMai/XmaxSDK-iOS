import XCTest
@testable import XmaxSDK

final class XmaxLoggerTests: XCTestCase {
    func testFormattedMessagePrefixesEveryLine() {
        XCTAssertEqual(
            XmaxLogger.formattedMessage(
                "Upload started\nUpload finished",
                category: "Storage"
            ),
            "[Xmax][Storage] Upload started\n[Xmax][Storage] Upload finished"
        )
    }

    func testFormattedMessageOmitsEmptyCategory() {
        XCTAssertEqual(
            XmaxLogger.formattedMessage("Ready", category: "  "),
            "[Xmax] Ready"
        )
    }
}
