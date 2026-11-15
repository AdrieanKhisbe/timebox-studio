import XCTest
import TimeboxKit
import TimeboxBluetooth
import TimeboxCLIKit
import TimeboxUtilities

final class OriginalTimeboxTests: XCTestCase {
    // Actual original TimeBox-light notification; the same 23 bytes were read
    // through the paired TimeBox-audio's Classic Serial Port channel 4.
    private let captured = "01 1C 00 04 46 55 00 00 04 FF FF FF 64 05 14 00 00 3E E0 18 58 FF FF 00 00 FF FF FF 00 C2 0A 02"
    private let raw = Data([0,0,4,255,255,255,100,5,20,0,0,62,224,24,88,255,255,0,0,255,255,255,0])
    private let request = Data([1,3,6,0,0x46,0x49,0,2])
    // Actual full profile that restored all 23 settings bytes after a short
    // selector corrupted RGB to 4A0000. Includes escaped checksum high byte01.
    private let clock = Data([1,8,0,0x45,0,0,0,0x3E,0xE0,0x6B,3,4,2])
    private let address = "AA:BB:CC:DD:EE:01"

    func testDeviceIdentityIsSeparateFromProtocolFamily() {
        XCTAssertNotEqual(TimeboxModel.timebox, .mini)
        XCTAssertEqual(TimeboxModel.timebox.protocolFamily, .legacy11)
        XCTAssertEqual(TimeboxModel.mini.protocolFamily, .legacy11)
        XCTAssertEqual(TimeboxModel.evo.protocolFamily, .evo16)
        XCTAssertEqual(TimeboxModel.timebox.width, 11)
        XCTAssertEqual(TimeboxModel.timebox.alarmSlotCount, 3)
    }

    func testCapturedOriginalSettingsDecodeAcrossFragmentationAndKeepModelIdentity() throws {
        let wire = try HexStringParser.data(from: captured)
        var decoder = TimeboxResponseDecoder(model: .timebox)
        var frames: [TimeboxResponseFrame] = []
        for byte in wire { frames += try decoder.append(Data([byte])) }
        XCTAssertEqual(frames.count, 1)
        let status = try TimeboxStatusDecoder.decode(XCTUnwrap(frames.first).data, model: .timebox)
        XCTAssertEqual(status.model, .timebox)
        XCTAssertEqual(status.rawData, raw)
        XCTAssertEqual(status.mode, "clock")
        XCTAssertEqual(status.brightness, 20)
        XCTAssertEqual(status.lightBrightness, 100)
        XCTAssertEqual(TimeboxQuery<TimeboxStatus>.status(model: .timebox).request, request)
    }

    func testLegacyClockUsesCompleteCapturedFormatAndRGBInsteadOfShortSelector() throws {
        for model: TimeboxModel in [.timebox, .mini] {
            let status = try TimeboxStatusDecoder.decode(raw, model: model)
            let profile = try TimeboxDisplayProfile(channel: .clock, status: status)
            XCTAssertEqual(profile.model, model)
            XCTAssertEqual(try TimeboxPacketEncoder.encode(.displayProfile(profile), model: model), clock)
            XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.display(.clock()), model: model))
            var unknown = raw; unknown[9] = 2
            XCTAssertThrowsError(try TimeboxDisplayProfile(channel: .clock, status: TimeboxStatusDecoder.decode(unknown, model: model)))
            XCTAssertThrowsError(try TimeboxDisplayProfile(channel: .clock, status: TimeboxStatusDecoder.decode(raw + Data([0]), model: model)))
        }
        let profile = try TimeboxDisplayProfile(channel: .clock, status: TimeboxStatusDecoder.decode(raw, model: .mini))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.displayProfile(profile), model: .timebox))
    }

    func testOriginalClockCLIReadsBeforeWritingAndPreservesLogicalTarget() throws {
        let h = CommandHarness()
        h.configuration = .init(defaultName: "old-timebox", devices: ["old-timebox": .init(mac: address, model: .timebox)])
        h.transport.replyChunks = [try HexStringParser.data(from: captured)]
        XCTAssertEqual(h.run(["display", "clock", "--channel", "4", "--json"]), 0, h.stderr.joined())
        XCTAssertEqual(h.transport.packets, [request, clock])
        XCTAssertEqual(h.transport.connections.count, 2)
        XCTAssertTrue(h.transport.connections.allSatisfy { $0.0 == address && $0.1 == 4 })
        XCTAssertTrue(h.rawStdout.contains("\"model\":\"timebox\""))
        XCTAssertTrue(h.rawStdout.contains("\"preserved_profile\":true"))
    }

    func testOriginalClockReadFailureNeverWritesGuessedDefaults() {
        let h = CommandHarness()
        XCTAssertEqual(h.run(["display", "clock", "--address", address, "--model", "timebox", "--timeout", "0.001", "--json"]), 1)
        XCTAssertEqual(h.transport.packets, [request])
        XCTAssertFalse(h.rawStdout.contains("\"status\":\"sent\""))
        let mock = CommandHarness()
        XCTAssertEqual(mock.run(["display", "clock", "--address", address, "--model", "timebox", "--mock"]), 1)
        XCTAssertTrue(mock.transport.connections.isEmpty)
    }

    func testOriginalREPLStatusClockAndBrightnessKeepTheirModelAndChannel() throws {
        let h = CommandHarness()
        h.transport.replyChunks = [try HexStringParser.data(from: captured), try HexStringParser.data(from: captured)]
        h.input = ["status", "display clock", "brightness 42", "target", "quit"]
        XCTAssertEqual(h.run(["repl", "--address", address, "--model", "timebox", "--channel", "4"]), 0, h.stderr.joined())
        XCTAssertTrue(h.stderr.isEmpty)
        XCTAssertEqual(h.transport.packets, [request, request, clock, Data([1,4,0,0x74,42,0xA2,0,2])])
        XCTAssertTrue(h.transport.connections.allSatisfy { $0.1 == 4 })
        XCTAssertTrue(h.stdout.joined().contains("model: timebox (explicit)"))
    }

    func testOriginalModelConfigSurvivesSaveRenameAndDefaultSelection() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "# retained\ndefault: old-timebox\ndevices:\n  old-timebox:\n    mac: AA:BB:CC:DD:EE:01\n    model: timebox # original model\n".write(to: file, atomically: true, encoding: .utf8)
        let config = DeviceConfigFile(url: file)
        XCTAssertEqual(try config.read().configuration.devices["old-timebox"]?.model, .timebox)
        try config.saveDiscovered([.init(name: "TimeBox-audio", address: address, isPaired: true, isConnected: true, source: .bluetooth)])
        try config.rename("old-timebox", to: "original")
        try config.select("original")
        XCTAssertEqual(try config.read().configuration.devices["original"]?.model, .timebox)
        XCTAssertTrue(try config.read().text.contains("model: timebox # original model"))
    }

    func testOriginalAnimationMetadataKeepsDeviceModelWhileSharingLegacyPackets() throws {
        let red = PixelFrame(fill: .init(red: 255, green: 0, blue: 0), model: .timebox)
        let green = PixelFrame(fill: .init(red: 0, green: 255, blue: 0), model: .timebox)
        let source = try TimeboxAnimation(frames: [.init(image: red, durationMilliseconds: 500), .init(image: green, durationMilliseconds: 500)])
        let original = try TimeboxAnimationEncoder.prepare(source, model: .timebox)
        let mini = try TimeboxAnimationEncoder.prepare(source, model: .mini)
        XCTAssertEqual(original.model, .timebox)
        XCTAssertEqual(original.packets, mini.packets)
        XCTAssertEqual(original.effectiveFrames, 2)
        let still = try TimeboxAnimationEncoder.prepare(TimeboxAnimation(frames: [source.frames[0]]), model: .timebox)
        XCTAssertEqual(still.model, .timebox)
        XCTAssertTrue(still.isStatic)
    }

    func testOriginalRejectsEvoOnlyFeaturesBeforeOpeningTransport() {
        for args in [["countdown", "start", "00:10"], ["design", "1"], ["display", "clock", "--style", "2"], ["text", "hello"]] {
            let h = CommandHarness()
            XCTAssertEqual(h.run(args + ["--address", address, "--model", "timebox", "--json"]), 1, args.joined(separator: " "))
            XCTAssertTrue(h.transport.connections.isEmpty)
            XCTAssertTrue(h.transport.packets.isEmpty)
        }
    }
}
