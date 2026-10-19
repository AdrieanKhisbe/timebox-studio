import XCTest
import TimeboxKit
@testable import TimeboxBluetooth
import Yams

final class MiniStatusTests: XCTestCase {
    // Synthetic source-derived OldMode record: distinct light25/system75;
    // data10=231 deliberately cannot be mistaken for Evo system brightness.
    private let data = Data([2,0,0,1,2,3,25,0,75,1,231,0,3,4,5,6,7,8,9,10,11,12,13])
    // Independently summed unescaped length28 + 04/46/55 + data = 0x0267;
    // reserved bytes in both fields and checksum are escaped afterward.
    private let wire = Data([1,28,0,4,70,85,3,5,0,0,3,4,3,5,3,6,25,0,75,3,4,231,0,3,6,4,5,6,7,8,9,10,11,12,13,103,3,5,2])
    private let request = Data([1,3,6,0,0x46,0x49,0,2])
    private let address = "AA:BB:CC:DD:EE:01"

    func testMiniOffsetsDoNotReuseEvoBrightnessOrModeLabels() throws {
        let status = try TimeboxStatusDecoder.decode(data, model: .mini)
        XCTAssertEqual(status.model, .mini)
        XCTAssertEqual(status.brightness, 75)
        XCTAssertEqual(status.lightBrightness, 25)
        XCTAssertEqual(status.mode, "light")
        XCTAssertThrowsError(try TimeboxStatusDecoder.decode(data))
        let labels = ["clock", "temperature", "light", "special_light", "sound_light", "custom"]
        for (mode, label) in labels.enumerated() {
            var raw = data; raw[0] = UInt8(mode)
            XCTAssertEqual(try TimeboxStatusDecoder.decode(raw, model: .mini).mode, label)
        }
        for mode: UInt8 in [6, 0xFE] {
            var raw = data; raw[0] = mode; raw.append(contentsOf: [0xAC, 0xBD])
            let unknown = try TimeboxStatusDecoder.decode(raw, model: .mini)
            XCTAssertEqual(unknown.modeRaw, mode)
            XCTAssertNil(unknown.mode)
            XCTAssertEqual(unknown.rawData, raw)
        }
        XCTAssertThrowsError(try TimeboxDisplayProfile(channel: .light, status: status))
    }

    func testMiniRejectsIncompleteRecordsAndInvalidActualBrightnessFields() throws {
        for size in 0..<23 {
            XCTAssertThrowsError(try TimeboxStatusDecoder.decode(data.prefix(size), model: .mini))
        }
        for index in [6, 8] {
            var raw = data; raw[index] = 101
            XCTAssertThrowsError(try TimeboxStatusDecoder.decode(raw, model: .mini))
            for value: UInt8 in [0, 100] {
                raw[index] = value
                XCTAssertNoThrow(try TimeboxStatusDecoder.decode(raw, model: .mini))
            }
        }
    }

    func testMiniQueryHandlesEscapedFragmentedReplyAndGreetingOnFreshLink() throws {
        let connection = QueryConnection()
        connection.chunks = [Data([0,5,72,69]), Data([76,76,79,0]) + wire.prefix(15), Data(wire.dropFirst(15))]
        let status = try TimeboxStatusReader.read(from: connection, model: .mini)
        XCTAssertEqual(connection.request, request)
        XCTAssertEqual(status.rawData, data)
        XCTAssertFalse(connection.isConnected)
        XCTAssertNil(connection.onData)
        XCTAssertFalse(connection.access.queryInProgress)
        // Existing public entry points preserve their Evo framing/function types.
        XCTAssertEqual(TimeboxQuery<TimeboxStatus>.status.request, Data([1,3,0,0x46,0x49,0,2]))
        let decode: (Data) throws -> TimeboxStatus = TimeboxStatusDecoder.decode
        var evo = Data(repeating: 0, count: 20); evo[6] = 10; evo[10] = 90
        XCTAssertEqual(try decode(evo).brightness, 90)
    }

    func testMiniStatusCLIFormatsFreshDeviceValuesInJSONAndYAML() throws {
        for format in ["--json", "--yaml", "--yml"] {
            let h = CommandHarness(); h.transport.replyChunks = [wire]
            XCTAssertEqual(h.run(["status", "--address", address, "--model", "mini", format]), 0, h.stderr.joined())
            let result = try XCTUnwrap(Yams.load(yaml: h.rawStdout) as? NSDictionary)
            let fields = try XCTUnwrap(result["data"] as? NSDictionary)
            XCTAssertEqual(result["status"] as? String, "ok")
            XCTAssertEqual(fields["brightness"] as? Int, 75)
            XCTAssertEqual(fields["light_brightness"] as? Int, 25)
            XCTAssertEqual(fields["mode"] as? String, "light")
            XCTAssertEqual(h.transport.packets, [request])
            XCTAssertFalse(h.transport.isConnected)
        }
    }

    func testMiniFailuresNeverReturnCachedOrDefaultStatus() throws {
        for kind in ["timeout", "disconnect", "short", "checksum", "brightness"] {
            let h = CommandHarness()
            switch kind {
            case "disconnect": h.transport.disconnectOnQueryWait = true
            case "short": h.transport.replyChunks = [try TimeboxMiniEncoder.frame(Data([4,0x46,0x55]) + data.prefix(20))]
            case "checksum": var bad = wire; bad[bad.count-4] ^= 1; h.transport.replyChunks = [bad]
            case "brightness":
                var raw = data; raw[8] = 200
                h.transport.replyChunks = [try TimeboxMiniEncoder.frame(Data([4,0x46,0x55]) + raw)]
            default: break
            }
            XCTAssertEqual(h.run(["status", "--address", address, "--model", "mini", "--timeout", "0.001", "--json"]), 1, kind)
            let result = try XCTUnwrap(Yams.load(yaml: h.rawStdout) as? NSDictionary)
            let fields = try XCTUnwrap(result["data"] as? NSDictionary)
            XCTAssertEqual(result["status"] as? String, "error")
            XCTAssertNil(fields["brightness"])
            XCTAssertFalse(h.transport.isConnected)
        }
    }

    func testREPLStatusUsesCurrentModelAndRetainsItsSelectedControlChannel() throws {
        let h = CommandHarness()
        h.configuration = .init(defaultName: "mini", devices: ["mini": .init(mac: address, model: .mini), "evo": .init(mac: "AA:BB:CC:DD:EE:02", model: .evo)])
        h.input = ["status", "target evo", "status", "quit"]
        h.transport.replyChunks = [wire, try TimeboxStatusTests.sourcedFrame()]
        XCTAssertEqual(h.run(["repl", "--channel", "4"]), 0, h.stderr.joined())
        XCTAssertEqual(h.transport.packets, [request, Data([1,3,0,0x46,0x49,0,2])])
        XCTAssertEqual(h.transport.connections.map { $0.1 }, [4,4,4,nil,1,1])
        XCTAssertEqual(h.transport.writeTargets, [address, "AA:BB:CC:DD:EE:02"])
        XCTAssertTrue(h.stdout.contains { $0.contains("light (2)") && $0.contains("75%") })
        XCTAssertTrue(h.stdout.contains { $0.contains("clock (0)") && $0.contains("75%") })
    }

    func testCapturedMiniDifferentialIsolatesSystemBrightnessAndRestoresEveryField() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/validation/fixtures/mini-status-live.json"))) as? [String: Any])
        let records = try XCTUnwrap(fixture["sequence"] as? [[String: Any]])
        let states = try records.map { record -> TimeboxStatus in
            let fields = try XCTUnwrap(record["data"] as? [String: Any])
            let raw = Data(try XCTUnwrap(fields["raw_data"] as? [UInt8]))
            let connection = QueryConnection()
            // Captured data, reconstructed frame; not original notification bytes.
            connection.chunks = [try TimeboxMiniEncoder.frame(Data([4,0x46,0x55]) + raw)]
            return try TimeboxStatusReader.read(from: connection, model: .mini)
        }
        XCTAssertEqual(states.map(\.modeRaw), [0,0,2,0])
        XCTAssertEqual(states.map(\.brightness), [20,80,20,20])
        XCTAssertEqual(states.map(\.lightBrightness), [80,80,80,80])
        let changed = zip(states[0].rawData, states[1].rawData).enumerated().compactMap { $0.element.0 == $0.element.1 ? nil : $0.offset }
        XCTAssertEqual(changed, [8])
        XCTAssertEqual(states.first?.rawData, states.last?.rawData)
    }
}
