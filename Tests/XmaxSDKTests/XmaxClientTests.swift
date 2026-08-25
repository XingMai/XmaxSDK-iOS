import XCTest
@testable import XmaxSDK

final class XmaxClientTests: XCTestCase {
    @MainActor
    func testCreateRealtimeManagerReturnsPublicRealtimeInterface() {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: "test-key")
        )
        let options = RealtimeConfiguration(model: .x2_0)

        let manager: any XmaxRealtimeManaging = client.createRealtimeManager(
            options: options
        )

        XCTAssertEqual(manager.options, options)
    }

    @MainActor
    func testCreateRealtimeManagerAllowsLocalPreviewWithoutAPIKey() {
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: " ")
        )

        let manager = client.createRealtimeManager(
            options: RealtimeConfiguration(model: .x2_0)
        )

        XCTAssertEqual(manager.options.model, .x2_0)
    }

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
