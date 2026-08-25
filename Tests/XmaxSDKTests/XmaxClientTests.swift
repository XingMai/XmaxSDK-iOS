import XCTest
@testable import XmaxSDK

final class XmaxClientTests: XCTestCase {
    func testCreateStorageManagerReturnsPublicStorageInterface() throws {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: "test-key")
        )

        let manager: any XmaxStorageManaging = try client.createStorageManager()

        XCTAssertTrue(manager is XmaxStorageManager)
    }

    func testCreateStorageManagerRejectsInvalidConfiguration() {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: " ")
        )

        XCTAssertThrowsError(try client.createStorageManager()) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidAPIKey,
                    message: "API key cannot be empty"
                )
            )
        }
    }
}
