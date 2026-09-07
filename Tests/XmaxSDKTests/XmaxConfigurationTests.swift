import XCTest
@testable import XmaxSDK

final class XmaxConfigurationTests: XCTestCase {
    func testConfigurationTrimsAPIKey() throws {
        let configuration = XmaxConfiguration(apiKey: "  test-key\n")

        XCTAssertEqual(configuration.apiKey, "test-key")
        XCTAssertEqual(configuration.environment, .china)
        XCTAssertTrue(configuration.loggerOptions.isEmpty)
        XCTAssertNoThrow(try configuration.validate())
    }

    func testGlobalEnvironmentUsesGlobalAPIBaseURL() {
        let configuration = XmaxConfiguration(
            apiKey: "test-key",
            environment: .global
        )

        XCTAssertEqual(configuration.environment, .global)
        XCTAssertEqual(
            configuration.environment.apiBaseURL.absoluteString,
            "https://api.xmax.cloud/open/api/v1"
        )
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

    func testRealtimeConfigurationKeepsModelAndEnablesInterpolationByDefault() {
        let configuration = RealtimeConfiguration(model: .x2_0)

        XCTAssertEqual(configuration.model.rawValue, "x2.0")
        XCTAssertTrue(configuration.isFrameInterpolationEnabled)
    }
}
