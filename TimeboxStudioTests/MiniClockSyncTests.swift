import XCTest
import TimeboxKit
import TimeboxCLIKit
@testable import TimeboxBluetooth

final class MiniClockSyncTests: XCTestCase {
    private let date = ISO8601DateFormatter().date(from: "2026-01-02T03:01:02Z")!
    private let zone = TimeZone(secondsFromGMT: 0)!
    // Source-derived Mini fixture: decimal year parts26,20; Friday5.
    // Interior month1/day2/hour3/minute1/second2 exercise OldMode escaping.
    private let mini = Data([1,11,0,24,26,20,3,4,3,5,3,6,3,4,3,5,5,95,0,2])
    private let evo = Data([1,11,0,24,26,20,1,2,3,1,2,5,95,0,2])

    func testCalendarSnapshotUsesSameFieldsWithDifferentModelFraming() throws {
        let snapshot = try TimeboxClockSnapshot(date: date, timeZone: zone)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.synchronizeClock(snapshot), model: .mini), mini)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.synchronizeClock(snapshot), model: .evo), evo)
    }

    func testAppDerivedMiniSundayAndLeapDayWireFixtures() throws {
        // Independently calculated from the current app's eight fields, then
        // sum16 over the unescaped interior and OldMode byte stuffing.
        let fixtures: [(String, [UInt8])] = [
            ("2026-03-02T01:02:03Z", [1,11,0,24,26,20,3,6,3,5,3,4,3,5,3,6,3,4,93,0,2]),
            ("2026-03-01T01:02:03Z", [1,11,0,24,26,20,3,6,3,4,3,4,3,5,3,6,0,91,0,2]),
            ("2000-02-29T03:02:01Z", [1,11,0,24,0,20,3,5,29,3,6,3,5,3,4,3,5,94,0,2])
        ]
        for (instant, expected) in fixtures {
            let snapshot = try TimeboxClockSnapshot(date: ISO8601DateFormatter().date(from: instant)!, timeZone: zone)
            XCTAssertEqual(try TimeboxPacketEncoder.encode(.synchronizeClock(snapshot), model: .mini), Data(expected), instant)
        }
    }

    func testMiniCLIUsesOneCapturedInstantAndReportsTransmission() {
        for format in ["--json", "--yaml"] {
            let cli = CommandHarness()
            var captures = 0
            cli.clock = { captures += 1; return self.date.addingTimeInterval(Double(captures - 1) * 86400) }
            cli.timeZone = { self.zone }
            XCTAssertEqual(cli.run(["time", "sync", "--address", "AA:BB:CC:DD:EE:01", "--model", "mini", format]), 0, cli.stderr.joined())
            XCTAssertEqual(captures, 1, "model selection must not recapture time across a day/weekday boundary")
            XCTAssertEqual(cli.transport.packets, [mini])
            XCTAssertTrue(cli.rawStdout.contains("sent"))
            XCTAssertFalse(cli.rawStdout.contains("readback_matches"))
        }
    }

    func testMiniREPLAndLibraryUseNativeEscapingAndLeaveOtherCapabilitiesGuarded() async throws {
        let cli = CommandHarness()
        cli.clock = { self.date }; cli.timeZone = { self.zone }
        cli.input = ["time sync", "countdown start 00:05", "quit"]
        XCTAssertEqual(cli.run(["repl", "--address", "AA:BB:CC:DD:EE:01", "--model", "mini"]), 0)
        XCTAssertEqual(cli.transport.packets, [mini])
        XCTAssertTrue(cli.stderr.joined().contains("does not yet support"))
        let transport = MiniClockSyncTransport()
        let client = TimeboxClient(model: .mini, transport: transport)
        try await client.connect(to: .mock)
        try await client.synchronizeClock(at: date, timeZone: zone)
        XCTAssertEqual(transport.packets, [mini])
        client.disconnect()
    }
}

private final class MiniClockSyncTransport: TimeboxTransport {
    var isConnected = false
    var onConnectionChange: ((Bool) -> Void)?
    var packets: [Data] = []
    func connect(to device: TimeboxDevice) async throws { isConnected = true }
    func disconnect() { isConnected = false }
    func write(_ data: Data) async throws { packets.append(data) }
}
