import XCTest
import TimeboxCLIKit
import TimeboxBluetooth
import Yams

final class StructuredOutputTests: XCTestCase {
    func testImageRawWriteConnectAndWriteFailureUseTheSameResultContract() throws {
        let address = ["--address", "AA:BB:CC:DD:EE:01"]
        for (arguments, status, field, expected) in [
            (["image", "docs/validation/fixtures/evo-orientation.png"], "sent", "width", 16),
            (["send-hex", "01 02 03"], "sent", "bytes", 3),
            (["connect"], "ok", "channel", 1)] {
            let harness = CommandHarness()
            XCTAssertEqual(harness.run(arguments + address + ["--json"]), 0)
            let result = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? [String: Any])
            XCTAssertEqual(result["status"] as? String, status)
            XCTAssertEqual((result["data"] as? [String: Any])?[field] as? Int, expected)
            XCTAssertTrue(harness.stdout.isEmpty)
        }
        let harness = CommandHarness()
        harness.transport.failWrites = true
        XCTAssertEqual(harness.run(["brightness", "50"] + address + ["--yaml"]), 1)
        let result = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "error")
        XCTAssertEqual((result["data"] as? [String: Any])?["code"] as? String, "write_failed")
        XCTAssertTrue(harness.transport.packets.isEmpty)
    }
    func testYAMLAliasMatchesJSONAndUnnamedDevicesAreNull() throws {
        var results: [NSDictionary] = []
        for flag in ["--json", "--yaml", "--yml"] {
            let harness = CommandHarness()
            XCTAssertEqual(harness.run(["color", "#ff0000", "--address", "aa-bb-cc-dd-ee-01", "--mock", flag]), 0)
            let result = try XCTUnwrap(try Yams.load(yaml: harness.rawStdout) as? NSDictionary)
            results.append(result)
            XCTAssertEqual(result["status"] as? String, "simulated")
            XCTAssertEqual((result["device"] as? NSDictionary)?["name"] as? NSNull, NSNull())
            XCTAssertTrue(harness.stdout.isEmpty)
        }
        XCTAssertEqual(results[0], results[1])
        XCTAssertEqual(results[1], results[2])
    }

    func testListEmptyAndAllMetadataDoNotInventConnections() throws {
        let harness = CommandHarness()
        XCTAssertEqual(harness.run(["list", "--json"]), 0)
        var result = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? [String: Any])
        XCTAssertNil(result["device"])
        XCTAssertEqual(((result["data"] as? [String: Any])?["devices"] as? [Any])?.count, 0)
        harness.rawStdout = ""
        harness.paired = [TimeboxDevice(name: "Timebox audio", address: "aa-bb-cc-dd-ee-01", isPaired: true, isConnected: false, source: .bluetooth),
            TimeboxDevice(name: "Speaker", address: "AA:BB:CC:DD:EE:02", isPaired: true, isConnected: true, source: .bluetooth)]
        harness.configuration = .init(devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        XCTAssertEqual(harness.run(["list", "--all", "--yaml"]), 0)
        result = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? [String: Any])
        let devices = try XCTUnwrap((result["data"] as? [String: Any])?["devices"] as? [[String: Any]])
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0]["name"] as? String, "desk")
        XCTAssertEqual(devices[0]["mac"] as? String, "AA:BB:CC:DD:EE:01")
        XCTAssertEqual(devices[0]["connected"] as? Bool, false)
        XCTAssertEqual(devices[0]["paired"] as? Bool, true)
        XCTAssertEqual(devices[0]["source"] as? String, "bluetooth")
        XCTAssertEqual(devices[1]["name"] as? NSNull, NSNull())
        XCTAssertEqual(devices[1]["is_timebox"] as? Bool, false)
        XCTAssertTrue(harness.transport.connections.isEmpty)
        XCTAssertTrue(harness.stdout.isEmpty)
    }

    func testStructuredUsageTransportAndConfigFailuresRemainParseable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("config.yml").path
        try "devices: [".write(toFile: path, atomically: true, encoding: .utf8)
        let cases: [([String], Int32, String)] = [
            (["brightness", "101", "--json"], 2, "invalid_arguments"),
            (["brightness", "50", "--json", "--yaml"], 2, "invalid_arguments"),
            (["brightness", "50", "--device", "absent", "--yaml"], 1, "device_not_found"),
            (["brightness", "50", "--address", "AA:BB:CC:DD:EE:01", "--json"], 1, "connection_failed"),
            (["list", "--config", path, "--yml"], 1, "invalid_config"),
            (["scan-ble", "--json"], 1, "unsupported"),
            (["repl", "--yaml"], 2, "invalid_arguments")]
        for (arguments, exit, code) in cases {
            let harness = CommandHarness()
            harness.transport.failingAddress = "AA:BB:CC:DD:EE:01"
            XCTAssertEqual(harness.run(arguments), exit, "\(arguments)")
            let result = try XCTUnwrap(Yams.load(yaml: harness.rawStdout) as? [String: Any])
            XCTAssertEqual(result["status"] as? String, "error")
            XCTAssertEqual((result["data"] as? [String: Any])?["code"] as? String, code)
            XCTAssertFalse(harness.stderr.isEmpty)
            XCTAssertTrue(harness.stdout.isEmpty)
        }
    }

    func testSaveHintsStayOnStderrAndTerminalStylingRespectsNoColor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = CommandHarness()
        harness.paired = [.mock]
        XCTAssertEqual(harness.run(["list", "--save", "--json", "--config", root.appendingPathComponent("config.yml").path]), 0)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(harness.rawStdout.utf8)) as? [String: Any])
        XCTAssertTrue(harness.stderr.joined().contains("device select"))
        XCTAssertTrue(harness.stdout.isEmpty)
        for (terminal, noColor, styled) in [(true, false, true), (true, true, false), (false, false, false)] {
            harness.stdout = []
            harness.stdoutIsTerminal = terminal
            harness.environment = noColor ? ["NO_COLOR": ""] : [:]
            XCTAssertEqual(harness.run(["list"]), 0)
            XCTAssertEqual(harness.stdout.joined().contains("\u{001B}["), styled)
        }
    }
    func testBrightnessJSONReportsSentAndKeepsDiagnosticsOnStderr() throws {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        XCTAssertEqual(harness.run(["brightness", "50", "--json"]), 0)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(harness.rawStdout.utf8)) as? [String: Any])
        XCTAssertEqual(result["command"] as? String, "brightness")
        XCTAssertEqual(result["status"] as? String, "sent")
        XCTAssertEqual((result["device"] as? [String: Any])?["name"] as? String, "desk")
        XCTAssertEqual((result["data"] as? [String: Any])?["brightness"] as? Int, 50)
        XCTAssertTrue(harness.stdout.isEmpty)
        XCTAssertTrue(harness.stderr.joined().contains("Connecting"))
    }
}
