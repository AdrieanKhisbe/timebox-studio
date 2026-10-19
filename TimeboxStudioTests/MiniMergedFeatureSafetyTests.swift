import XCTest
import TimeboxKit
@testable import TimeboxBluetooth

final class MiniMergedFeatureSafetyTests: XCTestCase {
    func testMiniWriterRejectsBeforeCreatingQueryOrControlTransport() {
        let transport = MiniSafetyTransport()
        var factories = 0
        for selection: TimeboxDisplay in [.light(), .design(index: 1), .clock(style: .rainbow)] {
            XCTAssertThrowsError(try TimeboxDisplayWriter.perform(selection, device: .mock, model: .mini,
                makeTransport: { factories += 1; return transport })) {
                guard case .unsupported = $0 as? TimeboxModelError else { return XCTFail("\($0)") }
            }
        }
        XCTAssertEqual(factories, 0)
        XCTAssertEqual(transport.ioCount, 0)
    }

    #if os(macOS)
    func testMiniConnectedClientRejectsMergedEvoFeaturesWithoutWritingOrDroppingLink() async throws {
        let transport = MiniSafetyTransport()
        var factories = 0
        let client = TimeboxClient(model: .mini, transport: transport,
            displayTransportFactory: { factories += 1; return transport })
        try await client.connect(to: .mock)
        let operations: [() async throws -> Void] = [
            { try await client.display(.clock(style: .rainbow)) },
            { try await client.display(.design(index: 1)) },
            { try await client.startCountdown(TimeboxCountdownDuration("00:01")) },
            { try await client.stopCountdown() },
            { _ = try await client.send(text: "test") }
        ]
        for operation in operations {
            do { try await operation(); XCTFail("Expected unsupported Mini feature") }
            catch { guard case .unsupported = error as? TimeboxModelError else { return XCTFail("\(error)") } }
            XCTAssertTrue(client.isConnected)
        }
        XCTAssertEqual(factories, 0)
        XCTAssertEqual(transport.ioCount, 0)
        try await client.setBrightness(20)
        XCTAssertEqual(transport.packets, [try TimeboxMiniEncoder.encode(.setBrightness(20))])
        client.disconnect()
    }
    #endif
}

private final class MiniSafetyTransport: TimeboxTransport, TimeboxDisplayTransport {
    var isConnected = false
    var onConnectionChange: ((Bool) -> Void)?
    var onData: ((Data) -> Void)?
    var packets: [Data] = []
    var ioCount = 0
    func connect(to device: TimeboxDevice) async throws { isConnected = true }
    func disconnect() { isConnected = false }
    func write(_ data: Data) async throws { packets.append(data); ioCount += 1 }
    func connectForDisplay(to device: TimeboxDevice, channel: UInt8?) throws { ioCount += 1; isConnected = true }
    func writeDisplay(_ data: Data) throws { ioCount += 1 }
    func settleDisplay(milliseconds: Int) {}
    func beginQuery() throws { ioCount += 1 }
    func endQuery() {}
    func writeQuery(_ data: Data) throws { ioCount += 1 }
    func waitForQuery(milliseconds: Int) {}
}
