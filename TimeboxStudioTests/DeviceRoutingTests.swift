import XCTest
import TimeboxBluetooth
import TimeboxCLIKit

final class DeviceRoutingTests: XCTestCase {
    func device(_ name: String, _ mac: String) -> TimeboxDevice {
        TimeboxDevice(name: name, address: mac, isPaired: true, isConnected: false, source: .bluetooth)
    }
    func testExplicitLogicalNameWinsWithoutDiscoveringOrChangingDefault() throws {
        let configuration = DeviceConfiguration(defaultName: "other", devices: [
            "desk": ConfiguredDevice(mac: "AA:BB:CC:DD:EE:01", bluetoothName: "Timebox-Evo-audio"),
            "other": ConfiguredDevice(mac: "AA:BB:CC:DD:EE:02")
        ])
        let target = try DeviceResolver.resolve(name: "DESK", address: nil,
            environmentAddress: "AA:BB:CC:DD:EE:03", configuration: configuration) {
            XCTFail("Explicit selection must not need discovery")
            return []
        }
        XCTAssertEqual(target.device.address, "AA:BB:CC:DD:EE:01")
        XCTAssertEqual(target.logicalName, "desk")
        XCTAssertEqual(configuration.defaultName, "other")
    }

    func testEnvironmentPrecedesDefaultAndAddressPrecedesEnvironment() throws {
        let config = DeviceConfiguration(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        let environment = try DeviceResolver.resolve(name: nil, address: nil, environmentAddress: "aa-bb-cc-dd-ee-02", configuration: config) { [] }
        XCTAssertEqual(environment.device.address, "AA:BB:CC:DD:EE:02")
        let explicit = try DeviceResolver.resolve(name: nil, address: "AA:BB:CC:DD:EE:03", environmentAddress: "AA:BB:CC:DD:EE:02", configuration: config) { [] }
        XCTAssertEqual(explicit.device.address, "AA:BB:CC:DD:EE:03")
    }

    func testDefaultCanSelectOfflineDeviceWithoutDiscoveryFallback() throws {
        let config = DeviceConfiguration(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
        let target = try DeviceResolver.resolve(name: nil, address: nil, environmentAddress: nil, configuration: config) {
            XCTFail("An unavailable saved default must not select another device")
            return []
        }
        XCTAssertEqual(target.logicalName, "desk")
    }

    func testSoleAudioTimeboxIsEligibleAndDuplicateAddressesAreDeduplicated() throws {
        let audio = device("Timebox-Evo-audio", "aa-bb-cc-dd-ee-01")
        let target = try DeviceResolver.resolve(name: nil, address: nil, environmentAddress: nil, configuration: .init()) {
            [audio, audio, self.device("Speaker", "AA:BB:CC:DD:EE:02")]
        }
        XCTAssertEqual(target.device.address, audio.address)
    }

    func testAmbiguousDiscoveryAndUnknownNameFailInsteadOfChoosingAnotherDevice() {
        XCTAssertThrowsError(try DeviceResolver.resolve(name: nil, address: nil, environmentAddress: nil, configuration: .init()) {
            [self.device("Timebox one", "AA:BB:CC:DD:EE:01"), self.device("Timebox two", "AA:BB:CC:DD:EE:02")]
        }) { XCTAssertEqual(($0 as? CommandFailure)?.kind, "ambiguous_device") }
        XCTAssertThrowsError(try DeviceResolver.resolve(name: "missing", address: nil, environmentAddress: nil, configuration: .init()) {
            XCTFail("Unknown explicit names must not fall back to discovery")
            return []
        })
    }
}
