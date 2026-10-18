import XCTest
import TimeboxKit
import Yams

final class AlarmCommandTests: XCTestCase {
    func testWeekdaysImplyWeeklyRepetitionInCLIAndREPL() throws {
        let before = try AlarmQueryTests.capturedFrame()
        var recurring = before
        recurring[27] = 1; recurring[28] = 7; recurring[29] = 30; recurring[30] = 6; recurring[35] = 25
        recurring[recurring.count - 3] = 0x69
        let expected = Data([1, 13, 0, 0x43, 2, 1, 7, 30, 6, 2, 1, 0, 0, 25, 0x9A, 0, 2])
        let cli = CommandHarness()
        cli.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        cli.transport.replyChunks = [before, recurring]
        XCTAssertEqual(cli.run(["alarm", "set", "2", "--time", "07:30", "--days", "mon,tue", "--volume", "25", "--yml"]), 0, cli.stderr.joined())
        XCTAssertTrue(cli.transport.packets.contains(expected))
        let result = try XCTUnwrap(Yams.load(yaml: cli.rawStdout) as? NSDictionary)
        XCTAssertEqual(result["status"] as? String, "sent")
        let repl = CommandHarness()
        repl.configuration = cli.configuration
        repl.transport.replyChunks = [before, recurring]
        repl.input = ["alarm set 2 --time 07:30 --days mon,tue --volume 25", "target", "quit"]
        XCTAssertEqual(repl.run(["repl"]), 0)
        XCTAssertEqual(repl.transport.packets, cli.transport.packets)
        XCTAssertTrue(repl.stdout.joined().contains("Target: desk | AA:BB:CC:DD:EE:01 | connected"))
    }

    func testMissingSnapshotOrReadbackNeverReportsSuccessfulAlarmWrite() throws {
        for (responses, code, expectedWrites) in [
            ([Data](), "query_timeout", 0),
            ([try AlarmQueryTests.capturedFrame()], "invalid_response", 1),
            ([try AlarmQueryTests.capturedFrame(), try AlarmQueryTests.capturedFrame()], "invalid_response", 1)] {
            let harness = CommandHarness()
            harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
            harness.transport.replyChunks = responses
            XCTAssertEqual(harness.run(["alarm", "set", "2", "--time", "23:04", "--timeout", "0.01", "--json"]), 1)
            let result = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? NSDictionary)
            XCTAssertEqual(result["status"] as? String, "error")
            XCTAssertEqual((result["data"] as? NSDictionary)?["code"] as? String, code)
            XCTAssertEqual(harness.transport.packets.filter { $0.count > 3 && $0[3] == 0x43 }.count, expectedWrites)
        }
    }
    func testDisableRetainsTimeAndSoundAndRejectsInvalidSchedulesBeforeBluetooth() throws {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        let before = try AlarmQueryTests.capturedFrame()
        var enabled = before
        enabled[27] = 1; enabled[28] = 23; enabled[29] = 4
        enabled[enabled.count - 3] = 0x72
        var disabled = enabled
        disabled[27] = 0; disabled[disabled.count - 3] = 0x71
        harness.transport.replyChunks = [enabled, disabled]
        XCTAssertEqual(harness.run(["alarm", "disable", "2", "--json"]), 0, harness.stderr.joined())
        XCTAssertTrue(harness.transport.packets.contains(Data([1, 13, 0, 0x43, 2, 0, 23, 4, 0, 2, 1, 0, 0, 50, 0xA2, 0, 2])))
        for (arguments, exit) in [
            (["set", "2", "--time", "24:00"], Int32(2)),
            (["set", "10", "--time", "07:30"], 2),
            (["set", "2", "--time", "07:30", "--recurring"], 2),
            (["set", "2", "--time", "07:30", "--days", "mon,mon"], 2),
            (["set", "2", "--time", "07:30", "--recurrent"], 2),
            (["set", "2", "--time", "07:30", "--volume", "101"], 2),
            (["disable", "2", "--time", "07:30"], 2)] {
            let invalid = CommandHarness()
            XCTAssertEqual(invalid.run(["alarm"] + arguments + ["--json"]), exit, arguments.joined(separator: " "))
            XCTAssertTrue(invalid.transport.connections.isEmpty)
            XCTAssertTrue(invalid.transport.packets.isEmpty)
        }
    }
    func testSetOncePreservesSoundSettingsAndReturnsFreshReadback() throws {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        let before = try AlarmQueryTests.capturedFrame()
        var changed = before
        // Derived from the captured frame: slot2 starts at frame offset26.
        changed[27] = 1; changed[28] = 23; changed[29] = 4
        changed[changed.count - 3] = 0x72; changed[changed.count - 2] = 3
        harness.transport.replyChunks = [before, changed]
        XCTAssertEqual(harness.run(["alarm", "set", "2", "--time", "23:04", "--json"]), 0, harness.stderr.joined())
        let result = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? NSDictionary)
        XCTAssertEqual(result["command"] as? String, "alarm set")
        XCTAssertEqual(result["status"] as? String, "sent")
        let data = try XCTUnwrap(result["data"] as? NSDictionary)
        XCTAssertEqual(data["readback_matches"] as? Bool, true)
        XCTAssertEqual((data["alarm"] as? NSDictionary)?["time"] as? String, "23:04")
        XCTAssertEqual((data["alarm"] as? NSDictionary)?["sound_mode_raw"] as? Int, 2)
        XCTAssertTrue(harness.transport.packets.contains(Data([1, 13, 0, 0x43, 2, 1, 23, 4, 0, 2, 1, 0, 0, 50, 0xA3, 0, 2])))
    }
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
