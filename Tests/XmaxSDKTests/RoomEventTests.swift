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
        try assertRuntime(in: event)
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

    func testChangeConditionEventMatchesRoomProtocol() throws {
        let event = try decode(
            RoomEvent.changeCondition(
                userID: "user-id",
                taskID: "task-id",
                videoFormat: RealtimeVideoFormat(
                    width: 720,
                    height: 1280,
                    fps: 24
                ),
                context: RealtimeContext(prompt: "new prompt")
            )
        )

        XCTAssertEqual(event["event"] as? String, "change_condition")
        XCTAssertNil(event["condition_version"])
        try assertRuntime(in: event)
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
        try assertRuntime(in: stop)
        try assertRuntime(in: tracks)
        try assertRuntime(in: heartbeat)
    }
}

private extension RoomEventTests {
    func assertRuntime(in event: [String: Any]) throws {
        let runtime = try XCTUnwrap(event["runtime"] as? [String: String])
        XCTAssertEqual(runtime["platform"], "ios")
        XCTAssertEqual(runtime["sdk_version"], XmaxSDKInfo.version)
        XCTAssertFalse(runtime["os_version", default: ""].isEmpty)
        XCTAssertFalse(runtime["device_model", default: ""].isEmpty)
    }

    func decode(_ message: String) throws -> [String: Any] {
        let data = try XCTUnwrap(message.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
