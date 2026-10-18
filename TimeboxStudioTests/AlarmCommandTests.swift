import XCTest
import TimeboxKit
import Yams

final class AlarmCommandTests: XCTestCase {
    func testREPLListsCurrentDeviceAndResumesOnlyAfterSuccessfulRead() throws {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        harness.transport.replyChunks = [try AlarmQueryTests.capturedFrame()]
        harness.input = ["alarm list", "target", "brightness 50", "quit"]
        XCTAssertEqual(harness.run(["repl"]), 0)
        XCTAssertTrue(harness.stdout.joined().contains("0: enabled 10:00 wed"))
        XCTAssertTrue(harness.stdout.joined().contains("Target: desk | AA:BB:CC:DD:EE:01 | connected"))
        XCTAssertEqual(harness.transport.connections.count, 3)
        XCTAssertEqual(harness.transport.packets.count, 2) // Read + subsequent brightness.

        let timeout = CommandHarness()
        timeout.configuration = harness.configuration
        timeout.input = ["alarm list --timeout 0.01", "target", "brightness 50", "quit"]
        XCTAssertEqual(timeout.run(["repl"]), 0)
        XCTAssertTrue(timeout.stderr.joined().contains("Timed out"))
        XCTAssertTrue(timeout.stdout.joined().contains("Target: desk | AA:BB:CC:DD:EE:01 | disconnected"))
        XCTAssertEqual(timeout.transport.packets.count, 1) // No brightness after failed read.
    }

    func testMockUnknownDeviceAndInvalidCommandsNeverSendAnAlarmPacket() throws {
        for (arguments, exit) in [(["alarm", "list", "--mock", "--json"], Int32(1)),
                                  (["alarm", "list", "--device", "absent", "--json"], 1),
                                  (["alarm", "list", "extra", "--json"], 2),
                                  (["alarm", "list", "--timeout", "nan", "--json"], 2),
                                  (["alarm", "set", "0", "--json"], 2)] {
            let harness = CommandHarness()
            XCTAssertEqual(harness.run(arguments), exit)
            XCTAssertTrue(harness.transport.packets.isEmpty)
            XCTAssertTrue(harness.transport.connections.isEmpty)
            XCTAssertEqual((try Yams.load(yaml: harness.rawStdout) as? NSDictionary)?["status"] as? String, "error")
        }
    }
    func testCLIListsLiveAlarmsWithJSONYAMLParityAndNoCachedResult() throws {
        var results: [NSDictionary] = []
        for format in ["--json", "--yaml", "--yml"] {
            let harness = CommandHarness()
            harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
            harness.transport.replyChunks = [try AlarmQueryTests.capturedFrame()]
            XCTAssertEqual(harness.run(["alarm", "list", "--device", "DESK", format]), 0)
            let result = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? NSDictionary)
            results.append(result)
            XCTAssertEqual(result["command"] as? String, "alarm list")
            XCTAssertEqual(result["status"] as? String, "ok")
            let alarms = try XCTUnwrap((result["data"] as? NSDictionary)?["alarms"] as? [NSDictionary])
            XCTAssertEqual(alarms.count, 10)
            XCTAssertEqual(alarms[0]["time"] as? String, "10:00")
            XCTAssertEqual(alarms[0]["recurrence"] as? NSNull, NSNull())
            XCTAssertEqual(alarms[0]["sound_mode_raw"] as? Int, 3)
            XCTAssertEqual(alarms[9]["enabled"] as? Bool, false)
            XCTAssertTrue(harness.stdout.isEmpty)
            XCTAssertEqual(harness.transport.packets, [Data([1, 3, 0, 0x42, 0x45, 0, 2])])
            XCTAssertFalse(harness.transport.isConnected)
            harness.rawStdout = ""
            XCTAssertEqual(harness.run(["alarm", "list", "--timeout", "0.01", format]), 1)
            let failure = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? NSDictionary)
            XCTAssertEqual(failure["status"] as? String, "error")
            XCTAssertEqual((failure["data"] as? NSDictionary)?["code"] as? String, "query_timeout")
        }
        XCTAssertEqual(results[0], results[1])
        XCTAssertEqual(results[1], results[2])
    }
}
