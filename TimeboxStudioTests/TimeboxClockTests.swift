import XCTest
import TimeboxKit
import TimeboxCLIKit

final class TimeboxClockTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testDecimalYearAndSundayFixture() throws {
        let snapshot = try TimeboxClockSnapshot(date: date("2026-10-18T21:02:03Z"), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(snapshot.weekday, 0)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.synchronizeClock(snapshot)),
                       Data([1,11,0,0x18,26,20,10,18,21,2,3,0,135,0,2]))
    }
    func testLocalGregorianBoundaryLeapDayAndCentury() throws {
        let east = TimeZone(secondsFromGMT: 9 * 3600)!
        let boundary = try TimeboxClockSnapshot(date: date("2099-12-31T15:00:01Z"), timeZone: east)
        XCTAssertEqual(boundary.year, 2100); XCTAssertEqual(boundary.month, 1); XCTAssertEqual(boundary.day, 1)
        XCTAssertEqual(boundary.hour, 0); XCTAssertEqual(boundary.weekday, 5)
        let leap = try TimeboxClockSnapshot(date: date("2024-02-29T12:34:56Z"), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(leap.day, 29); XCTAssertEqual(leap.weekday, 4)
        let packet = try TimeboxPacketEncoder.encode(.synchronizeClock(boundary))
        XCTAssertEqual(Array(packet[4...5]), [0,21])
    }
    func testCLIUsesOneClockSnapshotAndReportsSent() throws {
        let harness = CommandHarness()
        var calls = 0
        harness.clock = { calls += 1; return self.date("2026-10-18T23:59:59Z") }
        harness.timeZone = { TimeZone(secondsFromGMT: 0)! }
        XCTAssertEqual(harness.run(["time", "sync", "--address", "AA:BB:CC:DD:EE:01", "--json"]), 0)
        XCTAssertEqual(calls, 1)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(harness.rawStdout.utf8)) as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "sent")
        XCTAssertEqual(harness.transport.packets.count, 1)
        XCTAssertEqual(Array(harness.transport.packets[0][4...11]), [26,20,10,18,23,59,59,0])
    }
    func testREPLSyncAndInvalidSyntaxNeverWrites() {
        let harness = CommandHarness()
        harness.input = ["time sync", "time", "quit"]
        XCTAssertEqual(harness.run(["repl", "--address", "AA:BB:CC:DD:EE:01"]), 0)
        XCTAssertEqual(harness.transport.packets.count, 1)
        let invalid = CommandHarness()
        XCTAssertEqual(invalid.run(["time", "sync", "extra"]), 2)
        XCTAssertTrue(invalid.transport.connections.isEmpty)
    }
}
