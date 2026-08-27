import XCTest
@testable import XmaxSDK

final class XmaxConfigurationTests: XCTestCase {
    func testConfigurationTrimsAPIKey() throws {
        let configuration = XmaxConfiguration(apiKey: "  test-key\n")

        XCTAssertEqual(configuration.apiKey, "test-key")
        XCTAssertTrue(configuration.loggerOptions.isEmpty)
        XCTAssertNoThrow(try configuration.validate())
    }

    func testConfigurationKeepsLoggerOptions() {
        let configuration = XmaxConfiguration(
            apiKey: "test-key",
            loggerOptions: [.business, .performance]
        )

        XCTAssertEqual(configuration.loggerOptions, .all)
    }

    func testEmptyAPIKeyFailsValidation() {
        let configuration = XmaxConfiguration(apiKey: " \n ")

        XCTAssertThrowsError(try configuration.validate()) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidAPIKey,
                    message: "API key cannot be empty"
                )
            )
        }
    }

    func testRealtimeConfigurationKeepsModel() {
        let configuration = RealtimeConfiguration(model: .x2_0)

        XCTAssertEqual(configuration.model.rawValue, "x2.0")
    }
}
