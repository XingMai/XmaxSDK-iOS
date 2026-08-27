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

    func testLoggerStateFiltersConfiguredOptions() {
        let state = XmaxLoggerState()

        XCTAssertFalse(state.isEnabled(.business))
        XCTAssertFalse(state.isEnabled(.performance))

        state.update(.business)

        XCTAssertTrue(state.isEnabled(.business))
        XCTAssertFalse(state.isEnabled(.performance))

        state.update(.all)

        XCTAssertTrue(state.isEnabled(.business))
        XCTAssertTrue(state.isEnabled(.performance))
        XCTAssertFalse(state.isEnabled([]))
    }
}
