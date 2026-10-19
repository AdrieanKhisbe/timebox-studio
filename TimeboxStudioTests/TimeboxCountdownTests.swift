import XCTest
import TimeboxKit

final class TimeboxCountdownTests: XCTestCase {
    func testReferenceFramesAndSupportedBoundaries() throws {
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.startCountdown(TimeboxCountdownDuration("05:00"))), Data([1,7,0,0x72,3,1,5,0,0x82,0,2]))
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.stopCountdown), Data([1,7,0,0x72,3,0,0,0,0x7c,0,2]))
        XCTAssertEqual(try TimeboxCountdownDuration("00:01").totalSeconds, 1)
        XCTAssertEqual(try TimeboxCountdownDuration("59:59").totalSeconds, 3599)
    }
    func testInvalidDurationsRejectedBeforeBluetooth() {
        for value in ["00:00", "60:00", "99:59", "00:60", "-1:05", "5:00", "005:00", "01:05:00", "05:00 ", "aa:bb", "００:０１", "999999999999:00"] {
            XCTAssertThrowsError(try TimeboxCountdownDuration(value), value)
            let h = CommandHarness()
            XCTAssertEqual(h.run(["countdown", "start", value, "--address", "AA:BB:CC:DD:EE:01"]), 2, value)
            XCTAssertTrue(h.transport.connections.isEmpty)
        }
        XCTAssertThrowsError(try TimeboxCountdownDuration(minutes: Int.max, seconds: 0))
        XCTAssertThrowsError(try TimeboxCountdownDuration(minutes: 1, seconds: -1))
    }
    func testCLIAndREPLSendCommandsAndFailuresAreReported() {
        let h = CommandHarness()
        XCTAssertEqual(h.run(["countdown", "start", "05:00", "--address", "AA:BB:CC:DD:EE:01", "--json"]), 0)
        XCTAssertTrue(h.rawStdout.contains("sent"))
        h.input = ["countdown start 00:05", "countdown stop", "quit"]
        XCTAssertEqual(h.run(["repl", "--address", "AA:BB:CC:DD:EE:01"]), 0)
        XCTAssertEqual(h.transport.packets.count, 3)
        h.transport.failWrites = true
        XCTAssertEqual(h.run(["countdown", "stop", "--address", "AA:BB:CC:DD:EE:01"]), 1)
    }
}
