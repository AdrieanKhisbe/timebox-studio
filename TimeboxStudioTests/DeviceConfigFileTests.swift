import XCTest
import TimeboxBluetooth
import TimeboxCLIKit

final class DeviceConfigFileTests: XCTestCase {
    func testInvalidConfigurationIsNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.yml")
        for invalid in ["devices: [", "default: missing\ndevices: {}\n",
            "devices: {desk: {mac: bad}}\n",
            "devices: {desk: {mac: 'AA:BB:CC:DD:EE:01'}, DESK: {mac: 'AA:BB:CC:DD:EE:02'}}\n",
            "devices: {desk: {mac: 'AA:BB:CC:DD:EE:01'}, other: {mac: 'aa-bb-cc-dd-ee-01'}}\n"] {
            try invalid.write(to: url, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try DeviceConfigFile(url: url).saveDiscovered([]))
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), invalid)
        }
    }

    func testFlowMappingAndUnwritableParent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.yml")
        let text = "# flow 🟦\n{devices: {desk: {mac: 'AA:BB:CC:DD:EE:01', bluetooth_name: 'Old'}}, future: true}\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        let device = TimeboxDevice(name: "Timebox", address: "aa-bb-cc-dd-ee-01", isPaired: true, isConnected: false, source: .bluetooth)
        let saved = try DeviceConfigFile(url: url).saveDiscovered([device])
        XCTAssertTrue(saved.text.contains("# flow 🟦"))
        XCTAssertTrue(saved.text.contains("future: true"))
        XCTAssertEqual(saved.configuration.defaultName, "desk")
        XCTAssertThrowsError(try DeviceConfigFile(url: url.appendingPathComponent("child.yml")).saveDiscovered([device]))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), saved.text)
    }
    func testRepeatedSaveHandlesCollisionsAndPreservesBlockScalarPunctuation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.yml")
        try "# header\r\ndevices:\r\n  desk:\r\n    mac: AA:BB:CC:DD:EE:01\r\n    bluetooth_name: Timebox, old [name]\r\n".write(to: url, atomically: true, encoding: .utf8)
        let devices = [1, 2, 3].map { TimeboxDevice(name: "Timebox", address: "AA:BB:CC:DD:EE:0\($0)", isPaired: true, isConnected: false, source: .bluetooth) }
        let file = DeviceConfigFile(url: url)
        let first = try file.saveDiscovered(devices)
        XCTAssertEqual(Set(first.configuration.devices.keys), ["desk", "Timebox", "Timebox-ddee03"])
        XCTAssertEqual(first.configuration.defaultName, "Timebox")
        XCTAssertTrue(first.text.contains("# header\r\n"))
        XCTAssertEqual(try file.saveDiscovered(devices).text, first.text)
    }
    func testSavingDiscoveryPreservesCommentsUnknownFieldsAndOfflineDevices() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.yml")
        let initial = """
        # My devices 🟦
        default: desk # selected
        theme: {color: blue} # future setting
        devices:
          desk: # do not rename this logical name
            mac: aa-bb-cc-dd-ee-01 # control endpoint
            bluetooth_name: Old name
            future: [1, 2, 3]
          offline:
            mac: AA:BB:CC:DD:EE:02

        """
        try initial.write(to: url, atomically: true, encoding: .utf8)
        let file = DeviceConfigFile(url: url)
        let discovery = TimeboxDevice(name: "Timebox renamed", address: "AA:BB:CC:DD:EE:01", isPaired: true, isConnected: false, source: .bluetooth)
        let saved = try file.saveDiscovered([discovery])
        XCTAssertEqual(saved.configuration.defaultName, "desk")
        XCTAssertEqual(saved.configuration.devices["desk"]?.bluetoothName, "Timebox renamed")
        XCTAssertNotNil(saved.configuration.devices["offline"])
        for text in ["# My devices 🟦", "# selected", "theme: {color: blue} # future setting", "# control endpoint", "future: [1, 2, 3]", "# do not rename this logical name"] {
            XCTAssertTrue(saved.text.contains(text), text)
        }
        XCTAssertEqual(try file.read().configuration, saved.configuration)
    }
}
