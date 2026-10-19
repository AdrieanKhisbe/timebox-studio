import XCTest
import CoreGraphics
@testable import TimeboxKit
@testable import TimeboxBluetooth
import TimeboxCLIKit

final class TimeboxMiniTests: XCTestCase {
    // Frozen independently calculated hass-divoom wire examples. No production encoder used.
    func testIndependentBrightnessColorAndReservedByteGoldens() throws {
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.setBrightness(42), model: .mini),
                       Data([1, 4, 0, 0x74, 42, 0xA2, 0, 2]))
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.lightningPlainColor(color: .init(red: 255, green: 0, blue: 128), brightnessPercent: 77), model: .mini),
                       Data([1, 9, 0, 0x45, 3, 5, 255, 0, 128, 77, 0, 28, 3, 5, 2]))
        // 1,2,3 in the body AND checksum require escaping. Length stays the unescaped 5.
        XCTAssertEqual(try TimeboxMiniEncoder.frame(Data([1, 2, 3])),
                       Data([1, 5, 0, 3, 4, 3, 5, 3, 6, 11, 0, 2]))
        XCTAssertEqual(try TimeboxMiniEncoder.frame(Data([246, 6])),
                       Data([1, 4, 0, 246, 6, 0, 3, 4, 2])) // checksum high byte 01
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.setBrightness(101), model: .mini))
    }

    func testRGB444PackingQuantizationOrientationAndOddTail() throws {
        var pixels = Array(repeating: PixelRGB(red: 0, green: 0, blue: 0), count: 121)
        pixels[0] = .init(red: 0x12, green: 0x34, blue: 0x56)
        pixels[1] = .init(red: 0x78, green: 0x9A, blue: 0xBC)
        pixels[11] = .init(red: 0, green: 255, blue: 0) // row two, column zero
        pixels[120] = .init(red: 0, green: 0, blue: 255)
        let frame = try PixelFrame(pixels: pixels, model: .mini)
        let interior = unescape(try TimeboxPacketEncoder.encode(.image(frame), model: .mini))
        XCTAssertEqual(Array(interior.prefix(7)), [189, 0, 0x44, 0, 10, 10, 4])
        XCTAssertEqual(Array(interior[7..<10]), [0x31, 0x75, 0xB9])
        // Pixel 11 is the second pixel of pair5: green in lower nibble of byte3.
        XCTAssertEqual(interior[7 + 5 * 3 + 2], 0x0F)
        XCTAssertEqual(Array(interior[(interior.count - 4)..<(interior.count - 2)]), [0, 15])
        XCTAssertEqual(interior.count, 191)
        let sum = interior.dropLast(2).reduce(0) { $0 + Int($1) } & 0xFFFF
        XCTAssertEqual(sum, Int(interior[189]) | Int(interior[190]) << 8)
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.image(frame)))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.image(PixelFrame()), model: .mini))
        var broken = frame; broken.pixels.removeLast()
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.image(broken), model: .mini))
    }

    func testImageConversionNativeSizeResizeAndBlackAlpha() throws {
        // DeviceRGB bytes, premultiplied RGBA. Native frame keeps top-left order.
        var bytes = [UInt8](repeating: 0, count: 121 * 4)
        for index in 0..<121 { bytes[index * 4 + 3] = 255 }
        bytes[0] = 255
        bytes[120 * 4 + 2] = 255
        let native = try ImageToPixelFrameConverter.pixelFrame(from: image(bytes, width: 11, height: 11), model: .mini)
        XCTAssertEqual(native.pixels.first, .init(red: 255, green: 0, blue: 0))
        XCTAssertEqual(native.pixels.last, .init(red: 0, green: 0, blue: 255))
        let resized = try ImageToPixelFrameConverter.pixelFrame(from: image([128, 0, 0, 128], width: 1, height: 1), model: .mini)
        XCTAssertEqual(resized.pixels.count, 121)
        XCTAssertTrue(resized.pixels.allSatisfy { $0 == PixelRGB(red: 128, green: 0, blue: 0) })
        let transparent = try ImageToPixelFrameConverter.pixelFrame(from: image([0, 0, 0, 0], width: 1, height: 1), model: .mini)
        XCTAssertTrue(transparent.pixels.allSatisfy { $0 == PixelRGB(red: 0, green: 0, blue: 0) })
    }

    func testOldEvoDesignAndMiniFrameCodableRoundTrip() throws {
        let evo = PixelFrame()
        let bytes = try JSONEncoder().encode(evo)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("width"))
        XCTAssertEqual(try JSONDecoder().decode(PixelFrame.self, from: bytes), evo)
        let mini = PixelFrame(model: .mini)
        XCTAssertEqual(try JSONDecoder().decode(PixelFrame.self, from: JSONEncoder().encode(mini)), mini)
    }

    func testConservativeResolutionPrecedenceConflictsAndRenamedDevice() throws {
        XCTAssertEqual(try TimeboxModelResolver.resolve(explicit: .mini, saved: .evo, detected: [.evo]).source, .explicit)
        XCTAssertEqual(try TimeboxModelResolver.resolve(saved: .mini, detected: [.evo]).model, .mini)
        XCTAssertEqual(try TimeboxModelResolver.resolve(saved: .mini, bypassSaved: true, detected: [.evo]).model, .evo)
        XCTAssertThrowsError(try TimeboxModelResolver.resolve(detected: [.evo, .mini]))
        for name in ["AKTBR", "Timebox Mini", "Timebox-Evo-audio", "Speaker"] {
            let device = TimeboxDevice(name: name, address: "AA:BB:CC:DD:EE:01", isPaired: true, isConnected: false, source: .bluetooth)
            XCTAssertTrue(TimeboxModelResolver.detectedModels(for: device).isEmpty)
        }
    }

    func testUnknownConflictingAndTimedOutIdentityNeverConnectOrWrite() {
        for models: Set<TimeboxModel> in [[], [.evo, .mini]] {
            let harness = CommandHarness(); harness.detectedModels = models
            XCTAssertEqual(harness.run(["color", "FF0000", "--address", "AA:BB:CC:DD:EE:01", "--json"]), 1)
            XCTAssertTrue(harness.transport.connections.isEmpty)
            XCTAssertTrue(harness.transport.packets.isEmpty)
            XCTAssertTrue(harness.stderr.joined().contains("--model"))
        }
        let transport = RecordingCommandTransport()
        let environment = CommandEnvironment(discover: { _ in [] }, makeTransport: { _ in transport },
            detectModels: { _ in throw CommandFailure("query_timeout", "Identity timed out") },
            output: { _ in }, errorOutput: { _ in }, rawOutput: { _ in })
        XCTAssertEqual(TimeboxCommandLine(environment: environment).run(arguments: ["color", "FF0000", "--address", "AA:BB:CC:DD:EE:01"]), 1)
        XCTAssertTrue(transport.connections.isEmpty)
    }

    func testDirectAddressOverrideAndStructuredModelSource() throws {
        let harness = CommandHarness(); harness.detectedModels = []
        XCTAssertEqual(harness.run(["color", "FF0080", "--brightness", "77", "--address", "AA:BB:CC:DD:EE:01", "--model", "mini", "--channel", "4", "--json"]), 0)
        XCTAssertEqual(harness.transport.connections.first?.1, 4)
        XCTAssertEqual(harness.transport.packets.first,
                       Data([1, 9, 0, 0x45, 3, 5, 255, 0, 128, 77, 0, 28, 3, 5, 2]))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(harness.rawStdout.utf8)) as? [String: Any])
        let device = try XCTUnwrap(result["device"] as? [String: Any])
        XCTAssertEqual(device["model"] as? String, "mini")
        XCTAssertEqual(device["model_source"] as? String, "explicit")
    }

    func testControlledAutomaticImageSelectionUsesMiniDimensionsAndReportsDetection() {
        let harness = CommandHarness(); harness.detectedModels = [.mini]
        XCTAssertEqual(harness.run(["image", "docs/validation/fixtures/evo-orientation.png", "--address", "AA:BB:CC:DD:EE:01", "--json"]), 0)
        XCTAssertTrue(harness.rawStdout.contains("\"width\":11"))
        XCTAssertTrue(harness.rawStdout.contains("\"model_source\":\"detected\""))
        XCTAssertEqual(unescape(harness.transport.packets[0]).count, 191)
    }

    func testSavedModelAutoBypassAndUnsupportedCountdownPreflight() {
        let harness = CommandHarness(); harness.detectedModels = []
        harness.configuration = .init(defaultName: "mini", devices: ["mini": .init(mac: "AA:BB:CC:DD:EE:01", model: .mini)])
        XCTAssertEqual(harness.run(["brightness", "3", "--json"]), 0)
        XCTAssertTrue(harness.rawStdout.contains("config"))
        let previousConnections = harness.transport.connections.count
        XCTAssertEqual(harness.run(["countdown", "start", "00:30"]), 1)
        XCTAssertEqual(harness.transport.connections.count, previousConnections)
        XCTAssertTrue(harness.stderr.joined().contains("Mini"))
        XCTAssertEqual(harness.run(["brightness", "50", "--model", "auto"]), 1)
        XCTAssertEqual(harness.transport.connections.count, previousConnections)
    }

    func testREPLTargetSwitchResolvesNewModelAndDoesNotLeakStartupOverride() {
        let harness = CommandHarness(); harness.detectedModels = []
        harness.configuration = .init(defaultName: "mini", devices: [
            "mini": .init(mac: "AA:BB:CC:DD:EE:01"),
            "evo": .init(mac: "AA:BB:CC:DD:EE:02", model: .evo),
            "unknown": .init(mac: "AA:BB:CC:DD:EE:03")])
        harness.input = ["color FF0000", "countdown start 00:30", "target evo", "color FF0000", "target unknown", "target", "color FF0000", "quit"]
        XCTAssertEqual(harness.run(["repl", "--model", "mini", "--channel", "4"]), 0)
        XCTAssertEqual(harness.transport.connections.count, 2)
        XCTAssertNil(harness.transport.connections.last?.1)
        XCTAssertEqual(harness.transport.packets.count, 3)
        XCTAssertEqual(unescape(harness.transport.packets[0])[3], 2) // Mini light mode
        XCTAssertEqual(harness.transport.packets[1][4], 1) // Evo light mode
        XCTAssertEqual(harness.transport.writeTargets, ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02", "AA:BB:CC:DD:EE:02"])
        XCTAssertTrue(harness.stdout.joined().contains("model: evo (config)"))
        XCTAssertTrue(harness.stderr.joined().contains("Target unchanged"))
    }

    func testSaveRenameAndSelectPreserveModelCommentsAndUnknownFields() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yml")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = "# keep\ndefault: desk\ndevices:\n  desk:\n    mac: 'AA:BB:CC:DD:EE:01'\n    model: mini # manual\n    future: true\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        let file = DeviceConfigFile(url: url)
        let device = TimeboxDevice(name: "Timebox", address: "AA:BB:CC:DD:EE:01", isPaired: true, isConnected: false, source: .bluetooth)
        XCTAssertEqual(try file.saveDiscovered([device]).configuration.devices["desk"]?.model, .mini)
        try file.rename("desk", to: "mini"); try file.select("mini")
        let saved = try file.read()
        XCTAssertEqual(saved.configuration.devices["mini"]?.model, .mini)
        XCTAssertTrue(saved.text.contains("model: mini # manual"))
        XCTAssertTrue(saved.text.contains("future: true"))
        try text.replacingOccurrences(of: "model: mini", with: "model: auto").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try file.read())
    }

    func testInvalidMiniAlarmSlotAndUnresolvedClientRejectBeforeTransport() async throws {
        let current = TimeboxAlarm(slot: 3, enabled: false, hour: 0, minute: 0, weekdayMask: 0, soundMode: 2, triggerMode: 1, frequencyBytes: [0, 0], volume: 50)
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.disableAlarm(current), model: .mini))
        let unresolved = TimeboxClient(model: nil)
        do { try await unresolved.setBrightness(50); XCTFail("Expected unknown model") }
        catch { XCTAssertEqual(error as? TimeboxModelError, .unidentified) }
        let mini = TimeboxClient(model: .mini)
        do { try await mini.disableAlarm(current); XCTFail("Expected invalid Mini slot") }
        catch { XCTAssertEqual(error as? TimeboxAlarmWriteError, .invalidSlot(3)) }
    }

    func testLibraryUsesSelectedModelThroughTransportBoundary() async throws {
        let transport = MiniRecordingTransport()
        let client = TimeboxClient(model: .mini, transport: transport)
        try await client.connect(to: .mock)
        try await client.setBrightness(42)
        try await client.setColor(.init(red: 255, green: 0, blue: 128), brightnessPercent: 77)
        try await client.send(image: PixelFrame(model: .mini))
        XCTAssertEqual(transport.packets[0], Data([1, 4, 0, 0x74, 42, 0xA2, 0, 2]))
        XCTAssertEqual(transport.packets[1], Data([1, 9, 0, 0x45, 3, 5, 255, 0, 128, 77, 0, 28, 3, 5, 2]))
        XCTAssertEqual(unescape(transport.packets[2]).count, 191)
        XCTAssertEqual(client.modelResolution?.model, .mini)
        client.disconnect()
        XCTAssertFalse(transport.isConnected)
    }

    private func unescape(_ packet: Data) -> [UInt8] {
        let wire = Array(packet.dropFirst().dropLast())
        var result: [UInt8] = [], index = 0
        while index < wire.count {
            if wire[index] == 3 { index += 1; result.append(wire[index] - 3) }
            else { result.append(wire[index]) }
            index += 1
        }
        return result
    }
    private func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

private final class MiniRecordingTransport: TimeboxTransport {
    var isConnected = false
    var onConnectionChange: ((Bool) -> Void)?
    var packets: [Data] = []
    func connect(to device: TimeboxDevice) async throws { isConnected = true }
    func disconnect() { isConnected = false }
    func write(_ data: Data) async throws { packets.append(data) }
}
