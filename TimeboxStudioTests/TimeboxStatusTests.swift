import XCTest
import TimeboxKit
import TimeboxBluetooth
import TimeboxUtilities
import Yams

final class TimeboxStatusTests: XCTestCase {
    static func sourcedFrame() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/validation/fixtures/evo-status-derived.json")))
        let fixture = try XCTUnwrap(object as? [String: Any])
        return try HexStringParser.data(from: XCTUnwrap(fixture["response"] as? String))
    }

    func testSourceDerivedSettingsDistinguishSystemAndLightBrightness() throws {
        let frame = try Self.sourcedFrame()
        let connection = QueryConnection()
        connection.chunks = [Data(frame.prefix(7)), Data(frame.dropFirst(7))]
        let status = try TimeboxStatusReader.read(from: connection)
        XCTAssertEqual(status.modeRaw, 0)
        XCTAssertEqual(status.mode, "clock")
        XCTAssertEqual(status.brightness, 75)
        XCTAssertEqual(status.lightBrightness, 50)
        XCTAssertEqual(status.rawData.count, 22)
        XCTAssertEqual(connection.request, Data([1, 3, 0, 0x46, 0x49, 0, 2]))
        XCTAssertFalse(connection.isConnected)
    }

    func testRejectsShortInvalidBrightnessAndPreservesUnknownModeAndExtensions() throws {
        let data = Data(try Self.sourcedFrame().dropFirst(6).dropLast(3))
        for size in 0..<20 { XCTAssertThrowsError(try TimeboxStatusDecoder.decode(data.prefix(size))) }
        for index in [6, 10] {
            var invalid = data; invalid[index] = 101
            XCTAssertThrowsError(try TimeboxStatusDecoder.decode(invalid))
        }
        var unknown = data; unknown[0] = 0xFE; unknown.append(contentsOf: [0xAC, 0xBD])
        let status = try TimeboxStatusDecoder.decode(unknown)
        XCTAssertEqual(status.modeRaw, 0xFE)
        XCTAssertNil(status.mode)
        XCTAssertEqual(status.rawData, unknown)
        var ambiguous = data; ambiguous[0] = 6
        XCTAssertNil(try TimeboxStatusDecoder.decode(ambiguous).mode)
        for value: UInt8 in [0, 100] {
            var boundary = data; boundary[6] = value; boundary[10] = value
            XCTAssertEqual(try TimeboxStatusDecoder.decode(boundary).brightness, Int(value))
        }
    }

    func testStatusCommandUsesResponseValuesAndJSONYAMLParity() throws {
        var results: [NSDictionary] = []
        for format in ["--json", "--yaml", "--yml"] {
            let cli = CommandHarness()
            cli.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
            cli.transport.replyChunks = [try Self.sourcedFrame()]
            XCTAssertEqual(cli.run(["status", format]), 0, cli.stderr.joined())
            let result = try XCTUnwrap(Yams.load(yaml: cli.rawStdout) as? NSDictionary)
            XCTAssertEqual(result["command"] as? String, "status")
            XCTAssertEqual(result["status"] as? String, "ok")
            let data = try XCTUnwrap(result["data"] as? NSDictionary)
            XCTAssertEqual(data["brightness"] as? Int, 75)
            XCTAssertEqual(data["light_brightness"] as? Int, 50)
            XCTAssertEqual(data["mode"] as? String, "clock")
            XCTAssertEqual(cli.transport.packets, [Data([1, 3, 0, 0x46, 0x49, 0, 2])])
            results.append(result)
        }
        XCTAssertEqual(results[0], results[1]); XCTAssertEqual(results[1], results[2])
    }

    func testStatusErrorsNeverReturnCachedOrPartialState() throws {
        for kind in ["timeout", "disconnect", "corrupt", "short"] {
            let cli = CommandHarness()
            cli.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")])
            switch kind {
            case "disconnect": cli.transport.disconnectOnQueryWait = true
            case "corrupt":
                var corrupt = try Self.sourcedFrame(); corrupt[corrupt.count - 2] ^= 1
                cli.transport.replyChunks = [corrupt]
            case "short": cli.transport.replyChunks = [try TimeboxPacketEncoder.encodePayload(Data([4, 0x46, 0x55, 0]))]
            default: break
            }
            XCTAssertEqual(cli.run(["status", "--timeout", "0.001", "--json"]), 1)
            let result = try XCTUnwrap(Yams.load(yaml: cli.rawStdout) as? NSDictionary)
            XCTAssertEqual(result["status"] as? String, "error")
            let data = try XCTUnwrap(result["data"] as? NSDictionary)
            XCTAssertNil(data["brightness"])
            XCTAssertFalse(cli.transport.isConnected)
        }
        for arguments in [["--mock"], ["extra"], ["--time", "07:30"], ["--days", "mon"], ["--volume", "10"]] {
            let cli = CommandHarness()
            XCTAssertNotEqual(cli.run(["status"] + arguments + ["--json"]), 0)
            XCTAssertTrue(cli.transport.packets.isEmpty)
            XCTAssertTrue(cli.transport.connections.isEmpty)
        }
    }

    func testREPLStatusTargetsCurrentDeviceAndResumesOnlyOnSuccess() throws {
        for succeeds in [true, false] {
            let cli = CommandHarness()
            cli.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01"), "other": .init(mac: "AA:BB:CC:DD:EE:02")])
            cli.input = ["target other", "status --timeout 0.001", "target", "quit"]
            if succeeds { cli.transport.replyChunks = [try Self.sourcedFrame()] }
            XCTAssertEqual(cli.run(["repl"]), 0)
            XCTAssertEqual(cli.transport.writeTargets.last, "AA:BB:CC:DD:EE:02")
            XCTAssertTrue(cli.stdout.contains { $0.contains("Target: other") && $0.contains(succeeds ? "| connected" : "| disconnected") })
            if succeeds { XCTAssertTrue(cli.stdout.contains { $0.contains("system brightness: 75%") }) }
        }
    }
}
