import XCTest
import TimeboxCLIKit

final class REPLTargetTests: XCTestCase {
    func testFailedSwitchLeavesNewTargetDisconnectedAndNeverWritesToOldDevice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.yml")
        let text = "# unchanged\ndefault: desk\ndevices: {desk: {mac: 'AA:BB:CC:DD:EE:01'}, offline: {mac: 'AA:BB:CC:DD:EE:02'}}\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        let harness = CommandHarness()
        harness.transport.failingAddress = "AA:BB:CC:DD:EE:02"
        harness.input = ["brightness 20", "target offline", "target", "target current", "brightness 80", "quit"]
        XCTAssertEqual(harness.run(["repl", "--config", url.path]), 0)
        XCTAssertEqual(harness.transport.writeTargets, ["AA:BB:CC:DD:EE:01"])
        XCTAssertEqual(harness.stdout.filter { $0.contains("Target: offline | AA:BB:CC:DD:EE:02 | disconnected") }.count, 2)
        XCTAssertTrue(harness.stderr.joined().contains("disconnected"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
    }
    func testSwitchesAreSessionOnlyUnknownTargetPreservesConnectionAndChannelIsPerDevice() {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "desk", devices: [
            "desk": .init(mac: "AA:BB:CC:DD:EE:01"), "Office desk": .init(mac: "AA:BB:CC:DD:EE:02")])
        harness.input = ["target", "target absent", "brightness 20", "target OFFICE DESK", "target current", "brightness 80", "quit"]
        XCTAssertEqual(harness.run(["repl", "--device", "DESK", "--channel", "4"]), 0)
        XCTAssertEqual(harness.transport.connections.map { $0.0 }, ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"])
        XCTAssertEqual(harness.transport.connections.map { $0.1 }, [4, nil])
        XCTAssertEqual(harness.transport.writeTargets, ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"])
        XCTAssertEqual(harness.configuration.defaultName, "desk")
        XCTAssertTrue(harness.stdout.joined().contains("Office desk"))
        XCTAssertTrue(harness.stderr.joined().contains("absent"))
    }
}
