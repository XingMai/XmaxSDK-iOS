import XCTest
@testable import XmaxSDK

final class RoomEventTests: XCTestCase {
    func testStartEventMatchesRoomProtocol() throws {
        let event = try decode(
            RoomEvent.start(
                userID: "user-id",
                taskID: "task-id",
                videoFormat: RealtimeVideoFormat(
                    width: 720,
                    height: 1280,
                    fps: 24
                ),
                context: RealtimeContext(
                    prompt: "a prompt",
                    referencePath: "cos/reference.png"
                )
            )
        )

        XCTAssertEqual(event["event"] as? String, "start")
        XCTAssertEqual(event["user_id"] as? String, "user-id")
        XCTAssertEqual(event["uid"] as? String, "task-id")
        let params = try XCTUnwrap(event["params"] as? [String: Any])
        XCTAssertEqual(params["model"] as? String, "default")
        XCTAssertEqual(params["size"] as? [Int], [720, 1280])
        XCTAssertEqual(params["prompt"] as? String, "a prompt")
        XCTAssertEqual(
            params["ref_image_path"] as? String,
            "cos/reference.png"
        )
    }

    func testStartEventOmitsMissingReferencePath() throws {
        let event = try decode(
            RoomEvent.start(
                userID: "user-id",
                taskID: "task-id",
                videoFormat: RealtimeVideoFormat(
                    width: 512,
                    height: 512,
                    fps: 24
                ),
                context: RealtimeContext(prompt: "a prompt")
            )
        )
        let params = try XCTUnwrap(event["params"] as? [String: Any])

        XCTAssertNil(params["ref_image_path"])
    }

    func testChangeConditionEventIncludesVersion() throws {
        let event = try decode(
            RoomEvent.changeCondition(
                userID: "user-id",
                taskID: "task-id",
                conditionVersion: 3,
                videoFormat: RealtimeVideoFormat(
                    width: 720,
                    height: 1280,
                    fps: 24
                ),
                context: RealtimeContext(prompt: "new prompt")
            )
        )

        XCTAssertEqual(event["event"] as? String, "change_condition")
        XCTAssertEqual(event["condition_version"] as? Int, 3)
    }

    func testStopTracksAndHeartbeatEventsMatchRoomProtocol() throws {
        let stop = try decode(
            RoomEvent.stop(userID: "user-id", taskID: "task-id")
        )
        let tracks = try decode(
            RoomEvent.tracks(
                userID: "user-id",
                taskID: "task-id",
                points: [
                    RealtimePoint(x: 12.5, y: 30),
                    RealtimePoint(x: 14, y: 32.5)
                ]
            )
        )
        let heartbeat = try decode(
            RoomEvent.heartbeat(userID: "user-id")
        )

        XCTAssertEqual(stop["event"] as? String, "stop")
        XCTAssertEqual(stop["user_id"] as? String, "user-id")
        XCTAssertEqual(stop["uid"] as? String, "task-id")
        XCTAssertEqual(tracks["event"] as? String, "tracks")
        XCTAssertEqual(
            tracks["tracks"] as? [[Double]],
            [[12.5, 30], [14, 32.5]]
        )
        XCTAssertEqual(heartbeat["event"] as? String, "heartbeat")
        XCTAssertEqual(heartbeat["user_id"] as? String, "user-id")
    }
}

private extension RoomEventTests {
    func decode(_ message: String) throws -> [String: Any] {
        let data = try XCTUnwrap(message.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
