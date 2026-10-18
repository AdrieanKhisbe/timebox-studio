import XCTest
import TimeboxCLIKit

final class DeviceManagementTests: XCTestCase {
    func testInteractiveDefaultsRenameCancellationAndInvalidEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.yml")
        let original = "default: desk\ndevices: {desk: {mac: 'AA:BB:CC:DD:EE:01'}, offline: {mac: 'AA:BB:CC:DD:EE:02'}} # keep\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        let config = ["--config", url.path]
        let harness = CommandHarness()
        for command in [["device", "select"], ["device", "rename"], ["device", "rename", "desk"],
                        ["device", "rename", "desk", "OFFLINE"], ["device", "rename", "desk", ""],
                        ["device", "select", "missing"]] {
            XCTAssertNotEqual(harness.run(command + config), 0)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
        }
        harness.interactive = true
        harness.input = ["q"]
        XCTAssertEqual(harness.run(["device", "select"] + config), 0)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
        harness.input = [""] // Default preselected, then EOF at rename prompt.
        XCTAssertEqual(harness.run(["device", "rename"] + config), 0)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
        harness.input = ["2"]
        XCTAssertEqual(harness.run(["device", "select"] + config), 0)
        XCTAssertEqual(try DeviceConfigFile(url: url).read().configuration.defaultName, "offline")
        harness.input = ["", "Office"]
        XCTAssertEqual(harness.run(["device", "rename"] + config), 0)
        XCTAssertEqual(try DeviceConfigFile(url: url).read().configuration.defaultName, "Office")
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("# keep"))
        XCTAssertTrue(harness.transport.connections.isEmpty)
    }

    func testConfigShowJSONHasNoEnvelopeAndMissingFileFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.yml")
        let harness = CommandHarness()
        let config = ["--config", url.path]
        XCTAssertEqual(harness.run(["config", "show"] + config), 1)
        XCTAssertEqual(harness.rawStdout, "")
        try "# notes\ndevices: {}\nfuture: {enabled: true, retries: 3}\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(harness.run(["config", "show", "--json"] + config), 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(harness.rawStdout.utf8)) as? [String: Any])
        XCTAssertNil(object["status"])
        XCTAssertEqual((object["future"] as? [String: Any])?["retries"] as? Int, 3)
        XCTAssertEqual((object["future"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertEqual(harness.run(["config", "show", "--json", "--yml"] + config), 2)
    }
    func testSelectAndRenameOfflineDevicePreserveConfigAndShowRawFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.yml")
        let initial = "# config 🟦\ndefault: desk # current\nfuture: [1, true]\ndevices:\n  desk: # keep annotation\n    mac: AA:BB:CC:DD:EE:01\n    bluetooth_name: Timebox One\n  offline:\n    mac: AA:BB:CC:DD:EE:02\n"
        try initial.write(to: url, atomically: true, encoding: .utf8)
        let harness = CommandHarness()
        let config = ["--config", url.path]
        XCTAssertEqual(harness.run(["device", "select", "OFFLINE"] + config), 0)
        XCTAssertEqual(harness.run(["device", "rename", "offline", "Office desk"] + config), 0)
        let saved = try DeviceConfigFile(url: url).read()
        XCTAssertEqual(saved.configuration.defaultName, "Office desk")
        XCTAssertEqual(saved.configuration.devices["Office desk"]?.mac, "AA:BB:CC:DD:EE:02")
        XCTAssertTrue(saved.text.contains("# current"))
        XCTAssertTrue(saved.text.contains("# keep annotation"))
        XCTAssertTrue(saved.text.contains("future: [1, true]"))
        XCTAssertEqual(harness.run(["config", "show", "--yml"] + config), 0)
        XCTAssertEqual(harness.rawStdout, saved.text)
        XCTAssertTrue(harness.transport.connections.isEmpty)
    }
}
