import XCTest
import TimeboxKit
@testable import TimeboxBluetooth
import TimeboxCLIKit

final class DisplayCommandTests: XCTestCase {
    func testIndependentEvoChannelClockAndEffectFixtures() throws {
        // node-divoom-timebox-evo tests/channels/{custom,time,vjeffects}.spec.ts
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.display(.design())),
                       Data([1, 4, 0, 0x45, 5, 0x4E, 0, 2]))
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.display(.clock(style: .fullScreen))),
                       Data([1, 13, 0, 0x45, 0, 1, 0, 1, 0, 0, 0, 255, 255, 255, 0x51, 3, 2]))

    }

    func testLightProfileEqualsEstablishedPlainColorEncodingAndValidatesBrightness() throws {
        let red = PixelRGB(red: 255, green: 0, blue: 0)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.display(.light(color: red))),
                       try TimeboxPacketEncoder.encode(.lightningPlainColor(color: red, brightnessPercent: 100)))
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.display(.light(brightnessPercent: 25))),
                       try TimeboxPacketEncoder.encode(.lightningPlainColor(color: .init(red: 255, green: 255, blue: 255), brightnessPercent: 25)))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.display(.light(color: red, brightnessPercent: -1))))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.display(.light(color: red, brightnessPercent: 101))))
    }

    func testUnverifiedPreservationAndDesignIndicesAreBlockedBeforePackets() {
        for selection: TimeboxDisplay in [.clock(), .light(), .effects(), .design(index: 0), .design(index: 255)] {
            XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.display(selection))) { error in
                XCTAssertTrue(error is TimeboxDisplayError)
            }
        }
        XCTAssertNil(TimeboxClockStyle(rawValue: 6))
        XCTAssertNil(TimeboxEffect(rawValue: 16))
    }

    func testLibraryOperationsUseTheActualTransportPath() async throws {
        let transport = DisplayRecordingTransport()
        let client = TimeboxClient(model: .evo, transport: transport)
        try await client.connect(to: .mock)
        try await client.display(.design())
        do { try await client.display(.effects(effect: .countdown)); XCTFail("Expected VJ gate") }
        catch { XCTAssertTrue(error is TimeboxDisplayError) }
        XCTAssertEqual(transport.packets, [Data([1, 4, 0, 0x45, 5, 0x4E, 0, 2])])
        do { try await client.display(.clock()); XCTFail("Expected preservation gate") }
        catch { XCTAssertEqual(error as? TimeboxQueryError, .unsupported) }
        XCTAssertEqual(transport.packets.count, 1)
        client.disconnect()
    }

    func testCLIAndREPLShareLibraryEncodingAndSelectors() throws {
        let arguments: [([String], TimeboxDisplay)] = [
            (["display", "clock", "--style", "5"], .clock(style: .analogRound)),
            (["display", "light", "--color", "123456", "--brightness", "25"], .light(color: .init(red: 0x12, green: 0x34, blue: 0x56), brightnessPercent: 25)),
            (["display", "design"], .design())
        ]
        for (args, selection) in arguments {
            let expected = try TimeboxPacketEncoder.encode(.display(selection))
            let oneShot = CommandHarness()
            XCTAssertEqual(oneShot.run(args + ["--address", "AA:BB:CC:DD:EE:01", "--json"]), 0)
            XCTAssertEqual(oneShot.transport.packets, [expected])
            XCTAssertTrue(oneShot.rawStdout.contains("sent"))
            let repl = CommandHarness()
            repl.input = [args.joined(separator: " "), "quit"]
            XCTAssertEqual(repl.run(["repl", "--address", "AA:BB:CC:DD:EE:02"]), 0)
            XCTAssertEqual(repl.transport.packets, [expected])
        }
    }

    func testInvalidAndUnverifiedCommandsNeverConnectOrWrite() {
        let invalid = [["display", "clock", "--style", "6"], ["display", "clock", "--style", "-1"],
            ["display", "light", "--color", "ZZZZZZ"], ["display", "light", "--brightness", "101"],
            ["effect", "16"], ["effect", "-1"], ["effect", "10", "--color", "FF0000"],
            ["design", "-1"], ["display", "clock", "--color", "FF0000"], ["color", "FF0000", "--style", "1"]]
        let unsupported = [["effect", "0"], ["effect", "9"], ["effect", "15"], ["display", "effects"]]
        for (commands, expected) in [(invalid, Int32(2)), (unsupported, Int32(1))] {
            for args in commands {
                let harness = CommandHarness()
                XCTAssertEqual(harness.run(args + ["--address", "AA:BB:CC:DD:EE:01", "--json"]), expected, args.joined(separator: " "))
                XCTAssertTrue(harness.transport.connections.isEmpty)
                XCTAssertTrue(harness.transport.packets.isEmpty)
            }
        }
    }
}

private final class DisplayRecordingTransport: TimeboxTransport {
    var isConnected = false
    var onConnectionChange: ((Bool) -> Void)?
    var packets: [Data] = []
    func connect(to device: TimeboxDevice) async throws { isConnected = true }
    func disconnect() { isConnected = false }
    func write(_ data: Data) async throws { packets.append(data) }
}
