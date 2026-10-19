import XCTest
import TimeboxKit
import TimeboxCLIKit
import Yams

final class MiniCommandTests: XCTestCase {
    private let selectors = ["--address", "AA:BB:CC:DD:EE:01", "--model", "mini"]
    // Actual AKTBR OldMode response, independently captured by prototype fafb242.
    private let before = Data([1,35,0,4,66,85,0,0,0,0,0,0,3,4,0,0,50,3,4,0,0,0,0,0,3,4,0,0,50,3,5,0,0,0,0,0,3,4,0,0,50,90,3,4,2])
    private let after = Data([1,35,0,4,66,85,0,0,0,0,0,0,3,4,0,0,50,3,4,0,0,0,0,0,3,4,0,0,50,3,5,3,4,3,5,52,0,0,3,4,0,0,50,145,3,4,2])
    private let query = Data([1,3,6,0,66,69,0,2])

    func testClockAndStopwatchUseNativeMiniPacketsThroughCLIAndREPL() {
        let commands: [([String], Data)] = [
            (["display", "clock"], Data([1,5,0,69,0,3,4,75,0,2])),
            (["stopwatch", "start"], Data([1,5,0,69,6,3,4,81,0,2])),
            (["stopwatch", "stop"], Data([1,5,0,69,6,0,80,0,2])),
            (["stopwatch", "reset"], Data([1,5,0,69,6,3,5,82,0,2]))
        ]
        for (command, expected) in commands {
            let cli = CommandHarness()
            XCTAssertEqual(cli.run(command + selectors + ["--json"]), 0, cli.stderr.joined())
            XCTAssertEqual(cli.transport.packets, [expected])
            XCTAssertFalse(cli.rawStdout.contains("preserved_profile\":true"))
        }
        let repl = CommandHarness()
        repl.input = commands.map { $0.0.joined(separator: " ") } + ["quit"]
        XCTAssertEqual(repl.run(["repl"] + selectors), 0, repl.stderr.joined())
        XCTAssertEqual(repl.transport.packets, commands.map(\.1))
        XCTAssertEqual(repl.transport.connections.count, 1, "Mini clock must not query Evo settings or reconnect")
    }

    func testMiniAlarmListDecodesGreetingAndReportsThreeSlotsInBothFormats() throws {
        for format in ["--json", "--yaml"] {
            let cli = CommandHarness()
            cli.transport.replyChunks = [Data([0,5,72,69,76,76,79,0]) + before]
            XCTAssertEqual(cli.run(["alarm", "list"] + selectors + [format]), 0, cli.stderr.joined())
            let result = try XCTUnwrap(Yams.load(yaml: cli.rawStdout) as? NSDictionary)
            let data = try XCTUnwrap(result["data"] as? NSDictionary)
            let alarms = try XCTUnwrap(data["alarms"] as? [NSDictionary])
            XCTAssertEqual(alarms.count, 3)
            XCTAssertEqual(alarms.compactMap { $0["slot"] as? Int }, [0,1,2])
            XCTAssertEqual(cli.transport.packets, [query])
        }
    }

    func testSetAndDisableCompareUnescapedRecordAndPreserveBothOtherSlots() throws {
        let cli = CommandHarness()
        cli.transport.replyChunks = [before, after, after, before]
        XCTAssertEqual(cli.run(["alarm", "set", "2", "--time", "02:52"] + selectors + ["--json"]), 0, cli.stderr.joined())
        let set = Data([1,13,0,67,3,5,3,4,3,5,52,0,0,3,4,0,0,50,188,0,2])
        XCTAssertEqual(cli.transport.packets, [query, set, query])
        XCTAssertTrue(cli.rawStdout.contains("\"readback_matches\":true"))
        // Disabling retains time02:52 rather than restoring an unrelated zero-time record.
        let disabledRecord: [UInt8] = [2,0,2,52,0,0,1,0,0,50]
        var data = [UInt8](repeating: 0, count: 30)
        data.replaceSubrange(0..<10, with: [0,0,0,0,0,0,1,0,0,50])
        data.replaceSubrange(10..<20, with: [1,0,0,0,0,0,1,0,0,50])
        data.replaceSubrange(20..<30, with: disabledRecord)
        cli.transport.replyChunks = [after, try response(data)]
        XCTAssertEqual(cli.run(["alarm", "disable", "2"] + selectors + ["--json"]), 0, cli.stderr.joined())
        XCTAssertEqual(cli.transport.packets.last, query)
    }

    func testInvalidMiniSlotNeverQueriesAndMissingOrChangedReadbackCannotReportSuccess() throws {
        for operation in [["set", "3", "--time", "07:30"], ["disable", "9"]] {
            let cli = CommandHarness()
            XCTAssertEqual(cli.run(["alarm"] + operation + selectors + ["--json"]), 2)
            XCTAssertTrue(cli.transport.connections.isEmpty)
            XCTAssertTrue(cli.transport.packets.isEmpty)
        }
        for reply in [Data(), before, try response([0,1,0,0,0,0,1,0,0,50, 1,0,0,0,0,0,1,0,0,50, 2,1,2,52,0,0,1,0,0,50])] {
            let cli = CommandHarness()
            cli.transport.replyChunks = [before, reply]
            XCTAssertEqual(cli.run(["alarm", "set", "2", "--time", "02:52", "--timeout", "0.01"] + selectors + ["--json"]), 1)
            XCTAssertFalse(cli.rawStdout.contains("\"status\":\"sent\""))
            XCTAssertEqual(cli.transport.packets.count, 3, "one snapshot, one write, one readback; no automatic replay")
        }
    }

    func testAlarmREPLReconnectsAfterReadAndMiniClockStillWorks() {
        let cli = CommandHarness()
        cli.transport.replyChunks = [before]
        cli.input = ["alarm list", "display clock", "stopwatch reset", "quit"]
        XCTAssertEqual(cli.run(["repl"] + selectors + ["--channel", "4"]), 0, cli.stderr.joined())
        XCTAssertTrue(cli.stderr.isEmpty)
        XCTAssertTrue(cli.stdout.joined().contains("3 slots"))
        XCTAssertEqual(cli.transport.packets.first, query)
        XCTAssertEqual(cli.transport.packets.count, 3)
        XCTAssertEqual(cli.transport.connections.map { $0.1 }, [4,4,4], "same-target alarm queries retain the current control channel")
    }

    func testAlarmWriteFailureIsNotReplayed() {
        let cli = CommandHarness()
        cli.transport.replyChunks = [before]
        cli.transport.failOnWriteNumber = 2
        XCTAssertEqual(cli.run(["alarm", "set", "2", "--time", "02:52"] + selectors + ["--json"]), 1)
        XCTAssertEqual(cli.transport.connections.count, 2, "fresh snapshot and one write attempt only")
        XCTAssertEqual(cli.transport.packets, [query])
        XCTAssertTrue(cli.rawStdout.contains("write_failed"))
        XCTAssertFalse(cli.rawStdout.contains("readback_matches"))
    }

    private func response(_ data: [UInt8]) throws -> Data {
        try TimeboxMiniEncoder.frame(Data([4,0x42,0x55] + data))
    }
}
