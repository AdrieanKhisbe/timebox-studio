import XCTest
import TimeboxKit
import TimeboxCLIKit
@testable import TimeboxBluetooth

final class MiniLightTests: XCTestCase {
    // Actual baseline from the Mini status acceptance: blue80, system20, variant0.
    private let raw = Data([0,0,5,0,0,255,80,3,20,1,75,0,0,236,184,0,255,0,0,255,255,255,0])
    private let blue = PixelRGB(red: 0, green: 0, blue: 255)
    private let request = Data([1,3,6,0,0x46,0x49,0,2])
    // Independent4502blue/80/variant0: length9 + payload sums to0x019F.
    private let golden = Data([1,9,0,0x45,3,5,0,0,255,80,0,0x9F,3,4,2])
    private let address = "AA:BB:CC:DD:EE:01"
    private func response(_ bytes: Data) throws -> Data { try TimeboxMiniEncoder.frame(Data([4,0x46,0x55]) + bytes) }

    func testStoredMiniLightProfileAndExplicitPlainLightMatchIndependentFrame() throws {
        let status = try TimeboxStatusDecoder.decode(raw, model: .mini)
        let profile = try TimeboxDisplayProfile(channel: .light, status: status)
        XCTAssertEqual(profile.model, .mini)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.displayProfile(profile), model: .mini), golden)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.display(.light(color: blue, brightnessPercent: 80)), model: .mini), golden)
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.display(.light()), model: .mini))
        XCTAssertThrowsError(try TimeboxDisplayProfile(channel: .clock, status: status))
        for level in [-1,101] { XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.display(.light(brightnessPercent: level)), model: .mini)) }
    }

    func testUnknownVariantsExtensionsAndCrossModelProfilesAreNotWritten() throws {
        for variant: UInt8 in 0...4 {
            var value = raw; value[22] = variant
            XCTAssertNoThrow(try TimeboxDisplayProfile(channel: .light, status: TimeboxStatusDecoder.decode(value, model: .mini)))
        }
        for bytes in [raw + Data([0]), Data(raw.dropLast()) + Data([5])] {
            XCTAssertThrowsError(try TimeboxDisplayProfile(channel: .light, status: TimeboxStatusDecoder.decode(bytes, model: .mini)))
        }
        let mini = try TimeboxDisplayProfile(channel: .light, status: TimeboxStatusDecoder.decode(raw, model: .mini))
        let evo = try TimeboxDisplayProfile(channel: .light, status: TimeboxStatusDecoder.decode(Data(repeating: 0, count: 20)))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.displayProfile(mini)))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.displayProfile(evo), model: .mini))
    }

    func testCLIBareMiniLightReadsBeforeWritingWhileExplicitProfileNeedsNoQuery() throws {
        let h = CommandHarness(); h.transport.replyChunks = [try response(raw)]
        XCTAssertEqual(h.run(["display", "light", "--address", address, "--model", "mini", "--json"]), 0, h.stderr.joined())
        XCTAssertEqual(h.transport.packets, [request,golden])
        XCTAssertEqual(h.transport.connections.count, 2)
        XCTAssertTrue(h.rawStdout.contains("\"preserved_profile\":true"))
        let explicit = CommandHarness()
        XCTAssertEqual(explicit.run(["display", "light", "--color", "0000FF", "--brightness", "80", "--address", address, "--model", "mini", "--mock", "--json"]), 0)
        XCTAssertEqual(explicit.transport.packets, [golden])
        XCTAssertTrue(explicit.rawStdout.contains("\"preserved_profile\":false"))
        let mock = CommandHarness()
        XCTAssertEqual(mock.run(["display", "light", "--address", address, "--model", "mini", "--mock"]), 1)
        XCTAssertTrue(mock.transport.connections.isEmpty)
    }

    func testFailedPreservationNeverSendsControlOrInventsDefaults() throws {
        var unknown = raw; unknown[22] = 255
        for bytes: Data? in [nil, unknown, raw + Data([0xAA]), Data(raw.prefix(20))] {
            let h = CommandHarness()
            if let bytes { h.transport.replyChunks = [try response(bytes)] }
            XCTAssertEqual(h.run(["display", "light", "--address", address, "--model", "mini", "--timeout", "0.001", "--json"]), 1)
            XCTAssertEqual(h.transport.packets, [request])
            XCTAssertFalse(h.transport.isConnected)
            XCTAssertFalse(h.rawStdout.contains("\"status\":\"sent\""))
        }
    }

    func testREPLBareLightPreservesCurrentMiniChannelThenReturnsToClock() throws {
        let h = CommandHarness(); h.transport.replyChunks = [try response(raw)]
        h.input = ["display light", "display clock", "quit"]
        XCTAssertEqual(h.run(["repl", "--address", address, "--channel", "4", "--model", "mini"]), 0, h.stderr.joined())
        XCTAssertEqual(h.transport.packets, [request,golden,Data([1,5,0,0x45,0,3,4,0x4B,0,2])])
        XCTAssertTrue(h.transport.connections.allSatisfy { $0.0 == address && $0.1 == 4 })
        XCTAssertEqual(h.transport.connections.count, 4)
    }

    @MainActor
    func testLibraryUsesMiniFramingAndReconnectsOnlyAfterSuccessfulPreservation() async throws {
        let persistent = MiniLightPersistent()
        var queryData = raw
        var radios: [RecordingCommandTransport] = []
        let client = TimeboxClient(model: .mini, transport: persistent, displayTransportFactory: {
            let radio = RecordingCommandTransport()
            if radios.isEmpty { radio.replyChunks = [try! self.response(queryData)] }
            radios.append(radio); return radio
        })
        try await client.connect(to: .mock, channel: 4)
        try await client.display(.light(color: blue, brightnessPercent: 80))
        XCTAssertEqual(persistent.packets, [golden])
        XCTAssertTrue(radios.isEmpty)
        try await client.display(.light())
        XCTAssertEqual(radios.map(\.packets), [[request],[golden]])
        XCTAssertEqual(persistent.connects, 2)
        XCTAssertTrue(client.isConnected)
        radios.removeAll(); queryData[22] = 255
        do { try await client.display(.light()); XCTFail("Unknown variant must fail before control") }
        catch { XCTAssertTrue(error is TimeboxModelError) }
        XCTAssertEqual(radios.count, 1)
        XCTAssertEqual(radios[0].packets, [request])
        XCTAssertFalse(client.isConnected)
    }
}

private final class MiniLightPersistent: TimeboxTransport {
    var isConnected = false
    var onConnectionChange: ((Bool) -> Void)?
    var packets: [Data] = []
    var connects = 0
    func connect(to device: TimeboxDevice) async throws { connects += 1; isConnected = true }
    func disconnect() { isConnected = false }
    func write(_ data: Data) async throws { packets.append(data) }
}
