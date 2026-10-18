import XCTest
import TimeboxBluetooth
import TimeboxCLIKit

final class RecordingCommandTransport: CommandTransport {
    var isConnected = false
    var channel: UInt8? = 1
    var connections: [(String, UInt8?)] = []
    var packets: [Data] = []
    var writeTargets: [String] = []
    var failingAddress: String?
    func connect(to device: TimeboxDevice, channel: UInt8?) throws {
        connections.append((device.address, channel))
        if device.address == failingAddress { throw CommandFailure("connection_failed", "Device is offline") }
        isConnected = true
    }
    func write(_ packet: Data) throws {
        guard isConnected else { throw CommandFailure("write_failed", "Not connected") }
        packets.append(packet)
        writeTargets.append(connections.last!.0)
    }
    func wait(milliseconds: Int) {}
    func disconnect() { isConnected = false }
}

final class CommandHarness {
    var stdout: [String] = []
    var rawStdout = ""
    var stderr: [String] = []
    var input: [String] = []
    var paired: [TimeboxDevice] = []
    var configuration = DeviceConfiguration()
    let transport = RecordingCommandTransport()
    var environment: [String: String] = [:]
    var interactive = false
    func run(_ arguments: [String]) -> Int32 {
        let environment = CommandEnvironment(discover: { _ in self.paired },
            configuration: { path in
                if let path { return try DeviceConfigFile(path: path).read().configuration }
                return self.configuration
            }, makeTransport: { _ in self.transport },
            output: { self.stdout.append($0) }, errorOutput: { self.stderr.append($0) },
            rawOutput: { self.rawStdout += $0 },
            readLine: { self.input.isEmpty ? nil : self.input.removeFirst() },
            isInteractive: interactive, variables: environment)
        return TimeboxCommandLine(environment: environment).run(arguments: arguments)
    }
}

final class CommandLineIntegrationTests: XCTestCase {
    func testListSavePersistsEveryTimeboxWithoutPromptAndResolvesSavedDefault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("config.yml").path
        let harness = CommandHarness()
        harness.paired = [
            TimeboxDevice(name: "Timebox A", address: "AA:BB:CC:DD:EE:01", isPaired: true, isConnected: false, source: .bluetooth),
            TimeboxDevice(name: "Timebox B", address: "AA:BB:CC:DD:EE:02", isPaired: true, isConnected: false, source: .bluetooth),
            TimeboxDevice(name: "Speaker", address: "AA:BB:CC:DD:EE:03", isPaired: true, isConnected: false, source: .bluetooth)
        ]
        XCTAssertEqual(harness.run(["list", "--all", "--save", "--config", path]), 0)
        let saved = try DeviceConfigFile(path: path).read()
        XCTAssertEqual(saved.configuration.devices.count, 2)
        XCTAssertEqual(saved.configuration.defaultName, "Timebox A")
        XCTAssertTrue(harness.stderr.joined().contains("timeboxctl device select"))
        XCTAssertTrue(harness.stderr.joined().contains("timeboxctl device rename"))
        XCTAssertTrue(harness.transport.connections.isEmpty)
        XCTAssertEqual(harness.run(["brightness", "50", "--config", path]), 0)
        XCTAssertEqual(harness.transport.connections.last?.0, "AA:BB:CC:DD:EE:01")
    }
    func testBrightnessUsesTheResolvedLogicalDeviceAndClassicPacket() {
        let harness = CommandHarness()
        harness.configuration = DeviceConfiguration(devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        XCTAssertEqual(harness.run(["brightness", "50", "--device", "DESK"]), 0)
        XCTAssertEqual(harness.transport.connections.map { $0.0 }, ["AA:BB:CC:DD:EE:01"])
        XCTAssertEqual(harness.transport.packets, [Data([1, 4, 0, 0x74, 50, 0xAA, 0, 2])])
    }

    func testListFiltersAudioTimeboxesAndAllBroadensDiscoveryWithoutConnecting() {
        let harness = CommandHarness()
        harness.paired = [
            TimeboxDevice(name: "Timebox-Evo-audio", address: "AA:BB:CC:DD:EE:01", isPaired: true, isConnected: false, source: .bluetooth),
            TimeboxDevice(name: "Speaker", address: "AA:BB:CC:DD:EE:02", isPaired: true, isConnected: false, source: .bluetooth)
        ]
        XCTAssertEqual(harness.run(["list"]), 0)
        XCTAssertTrue(harness.stdout.joined().contains("Timebox-Evo-audio"))
        XCTAssertFalse(harness.stdout.joined().contains("Speaker"))
        harness.stdout = []
        XCTAssertEqual(harness.run(["list", "--all"]), 0)
        XCTAssertTrue(harness.stdout.joined().contains("Speaker"))
        XCTAssertTrue(harness.transport.connections.isEmpty)
    }

    func testConflictingSelectorsAndListSelectorsCauseNoDeviceWrites() {
        for args in [["brightness", "50", "--device", "desk", "--address", "AA:BB:CC:DD:EE:01"],
                     ["list", "--name", "desk"], ["list", "--address", "AA:BB:CC:DD:EE:01"]] {
            let harness = CommandHarness()
            XCTAssertEqual(harness.run(args), 2)
            XCTAssertTrue(harness.transport.packets.isEmpty)
            XCTAssertTrue(harness.transport.connections.isEmpty)
        }
    }

    func testColorImageAndReplAcceptNameAddressAndDefaultWithoutBLEDispatch() {
        for selector in [["--device", "DESK"], ["--name", "desk"], ["--address", "aa-bb-cc-dd-ee-01"], []] {
            for operation in [["color", "FF0000"], ["image", "docs/validation/fixtures/evo-orientation.png"], ["repl"]] {
                let harness = CommandHarness()
                harness.configuration = DeviceConfiguration(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
                harness.input = ["brightness 50", "quit"]
                XCTAssertEqual(harness.run(operation + selector), 0, "\(operation) \(selector)")
                XCTAssertEqual(harness.transport.connections.map { $0.0 }, ["AA:BB:CC:DD:EE:01"])
                XCTAssertFalse(harness.transport.packets.isEmpty)
            }
        }
    }

    func testFailedSelectedDeviceNeverFallsBackToSoleDiscoveredDevice() {
        let harness = CommandHarness()
        harness.transport.failingAddress = "AA:BB:CC:DD:EE:01"
        harness.configuration = DeviceConfiguration(defaultName: "offline", devices: ["offline": .init(mac: "AA:BB:CC:DD:EE:01")])
        harness.paired = [.mock]
        XCTAssertEqual(harness.run(["brightness", "50"]), 1)
        XCTAssertTrue(harness.transport.connections.allSatisfy { $0.0 == "AA:BB:CC:DD:EE:01" })
        XCTAssertTrue(harness.transport.packets.isEmpty)
    }
}
