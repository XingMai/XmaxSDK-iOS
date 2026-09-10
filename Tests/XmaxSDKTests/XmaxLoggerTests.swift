import XCTest
@testable import XmaxSDK

final class XmaxLoggerTests: XCTestCase {
    func testFormattedMessagePrefixesEveryLine() {
        XCTAssertEqual(
            XmaxLogger.storage.formattedMessage(
                message: "Upload started\nUpload finished"
            ),
            "[Xmax][Storage] Upload started\n[Xmax][Storage] Upload finished"
        )
    }

    func testLoggersPreserveCategoryPrefixes() {
        let loggers: [(XmaxLogger, String)] = [
            (.realtime, "Realtime"),
            (.rtc, "RTC"),
            (.media, "Media"),
            (.api, "API"),
            (.storage, "Storage"),
            (.room, "Room"),
            (.stream, "Stream"),
            (.render, "Render"),
            (.interaction, "Interaction"),
            (.permission, "Permission")
        ]

        for (logger, category) in loggers {
            XCTAssertEqual(
                logger.formattedMessage(message: "Ready"),
                "[Xmax][\(category)] Ready"
            )
        }
    }

    func testDisabledLogsDoNotEvaluateMessages() {
        XmaxLogger.configure(options: [])
        defer { XmaxLogger.configure(options: []) }
        var evaluationCount = 0

        func message() -> String {
            evaluationCount += 1
            return "Disabled log"
        }

        XmaxLogger.realtime.debug(message: message())
        XmaxLogger.realtime.info(message: message())
        XmaxLogger.realtime.warn(message: message())
        XmaxLogger.realtime.error(message: message())

        XCTAssertEqual(evaluationCount, 0)
    }

    func testLoggersShareConfigurationAndFilterPerformanceMessages() {
        XmaxLogger.configure(options: .business)
        defer { XmaxLogger.configure(options: []) }
        var evaluationCount = 0

        func message() -> String {
            evaluationCount += 1
            return "Logger configuration test"
        }

        XmaxLogger.realtime.debug(message: message())
        XmaxLogger.api.info(message: message())
        XmaxLogger.media.warn(message: message())
        XmaxLogger.storage.error(message: message())
        XmaxLogger.rtc.debug(message: message(), option: .performance)
        XmaxLogger.realtime.info(message: message(), option: .performance)

        XCTAssertEqual(evaluationCount, 4)

        XmaxLogger.configure(options: .performance)
        XmaxLogger.realtime.error(message: message())
        XmaxLogger.rtc.debug(message: message(), option: .performance)
        XmaxLogger.realtime.info(message: message(), option: .performance)

        XCTAssertEqual(evaluationCount, 6)
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
