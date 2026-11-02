import XCTest
import TimeboxKit
import TimeboxBluetooth
import TimeboxCLIKit

private final class ProbeTransport: TimeboxDisplayTransport {
    var onData: ((Data) -> Void)?
    var isConnected = false
    var ownsQuery = false
    var chunks: [Data] = []
    var packets: [Data] = []
    var targets: [(String, UInt8?)] = []
    var failConnect = false
    var disconnectOnWait = false
    var afterWrite: (() -> Void)?
    func connectForDisplay(to device: TimeboxDevice, channel: UInt8?) throws {
        targets.append((device.address, channel))
        if failConnect { throw TimeboxQueryError.disconnected }
        isConnected = true
    }
    func settleDisplay(milliseconds: Int) {}
    func writeDisplay(_ data: Data) throws { XCTFail("Detection must never send control writes") }
    func beginQuery() throws {
        guard !ownsQuery else { throw TimeboxQueryError.busy }
        ownsQuery = true
    }
    func endQuery() { ownsQuery = false }
    func writeQuery(_ data: Data) throws {
        XCTAssertTrue(ownsQuery)
        packets.append(data)
        afterWrite?()
    }
    func waitForQuery(milliseconds: Int) {
        if disconnectOnWait { isConnected = false; return }
        if !chunks.isEmpty { onData?(chunks.removeFirst()) }
        else { Thread.sleep(forTimeInterval: 0.001) }
    }
    func disconnect() { isConnected = false }
}

final class ProtocolDetectionTests: XCTestCase {
    private let address = "AA:BB:CC:DD:EE:01"
    private var device: TimeboxDevice { .init(name: "renamed speaker", address: address, isPaired: true, isConnected: false, source: .bluetooth) }
    private let legacy = Data([0,0,5,0,0,255,80,3,20,1,75,0,0,236,184,0,255,0,0,255,255,255,0])
    private let evo = Data([0,0,0,255,0,0,100,0,1,0,80,1,255,255,255,5,1,0,0,0])
    private let request = Data([1,3,0,0x46,0x49,0,2])
    private func frame(_ data: Data, legacy: Bool) throws -> Data {
        let body = Data([4,0x46,0x55]) + data
        return try legacy ? TimeboxLegacyEncoder.frame(body) : TimeboxPacketEncoder.encodePayload(body)
    }
    private func detect(_ transport: ProbeTransport) throws -> TimeboxProtocolDetection {
        try TimeboxProtocolDetector.detect(device: device, channel: 4, timeout: 0.02, makeTransport: { transport })
    }
    private func assertClean(_ transport: ProbeTransport, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(transport.isConnected, file: file, line: line)
        XCTAssertFalse(transport.ownsQuery, file: file, line: line)
        XCTAssertNil(transport.onData, file: file, line: line)
    }

    func testBothDialectsAcrossEveryFragmentBoundaryWithReservedBytes() throws {
        for (data, family) in [(evo, TimeboxProtocolFamily.evo16), (legacy, .legacy11)] {
            let wire = try frame(data, legacy: family == .legacy11)
            for split in 1..<wire.count {
                let t = ProbeTransport(); t.chunks = [Data(wire.prefix(split)), Data(wire.dropFirst(split))]
                let result = try detect(t)
                XCTAssertEqual(result.family, family)
                XCTAssertEqual(result.settings, data)
                XCTAssertGreaterThanOrEqual(result.elapsedMilliseconds, result.queryMilliseconds)
                XCTAssertEqual(t.packets, [request])
                XCTAssertEqual(t.targets.first?.0, address)
                XCTAssertEqual(t.targets.first?.1, 4)
                assertClean(t)
            }
        }
    }

    func testCapturedOriginalReplyAndGreetingsAreAcceptedWithoutModelGuess() throws {
        let original = Data([0,0,4,255,255,255,100,5,20,0,0,62,224,24,88,255,255,0,0,255,255,255,0])
        let greeting = Data([0,5,0x48,0x45,0x4C,0x4C,0x4F,0])
        let unrelated = try TimeboxLegacyEncoder.frame(Data([4,0x59,0x55,0]))
        let t = ProbeTransport()
        t.chunks = (greeting + unrelated + (try frame(original, legacy: true))).map { Data([$0]) }
        XCTAssertEqual(try detect(t).family, .legacy11)
        XCTAssertEqual(t.packets, [request])
        assertClean(t)
    }

    func testOnlyNoReplyRetriesEscapedSettingsReadOnFreshConnection() throws {
        let first = ProbeTransport(), second = ProbeTransport()
        second.chunks = [try frame(legacy, legacy: true)]
        var attempts = 0
        let result = try TimeboxProtocolDetector.detect(device: device, channel: 4, timeout: 0.02, makeTransport: {
            attempts += 1; return attempts == 1 ? first : second
        })
        XCTAssertEqual(result.family, .legacy11)
        XCTAssertEqual(first.packets, [request])
        XCTAssertEqual(second.packets, [Data([1,3,6,0,0x46,0x49,0,2])])
        XCTAssertEqual(attempts, 2)
        assertClean(first); assertClean(second)
    }

    func testUnknownCorruptAndInvalidRepliesNeverRetryOrSelectCodec() throws {
        var invalid = legacy; invalid[8] = 101
        var corrupt = try frame(legacy, legacy: true); corrupt[corrupt.count - 3] ^= 0x40
        let extendedEvo = evo + Data([0,0,0]) // raw reserved bytes are not legacy framing
        for wire in [try frame(legacy + Data([0]), legacy: true), try frame(invalid, legacy: true),
                     try frame(extendedEvo, legacy: false), corrupt, Data((try frame(evo, legacy: false)).dropLast())] {
            let t = ProbeTransport(); t.chunks = [wire]
            var attempts = 0
            XCTAssertThrowsError(try TimeboxProtocolDetector.detect(device: device, timeout: 0.01, makeTransport: { attempts += 1; return t }))
            XCTAssertEqual(attempts, 1)
            XCTAssertEqual(t.packets, [request])
            assertClean(t)
        }
    }

    func testConflictingSnapshotsRejectAndConnectionFailuresNeverRetry() throws {
        let t = ProbeTransport()
        t.chunks = [try frame(legacy, legacy: true) + frame(evo, legacy: false)]
        XCTAssertThrowsError(try detect(t)) { error in
            guard case TimeboxProtocolDetectionError.conflictingReplies = error else { return XCTFail("\(error)") }
        }
        assertClean(t)
        for disconnected in [false, true] {
            let failed = ProbeTransport(); failed.failConnect = !disconnected; failed.disconnectOnWait = disconnected
            var attempts = 0
            XCTAssertThrowsError(try TimeboxProtocolDetector.detect(device: device, makeTransport: { attempts += 1; return failed }))
            XCTAssertEqual(attempts, 1)
            assertClean(failed)
        }
    }

    func testCancellationAndBusyQueryPreserveOwnership() throws {
        let t = ProbeTransport()
        var cancelled = false
        t.afterWrite = { cancelled = true }
        XCTAssertThrowsError(try TimeboxProtocolDetector.detect(device: device, isCancelled: { cancelled }, makeTransport: { t }))
        assertClean(t)
        let busy = ProbeTransport(); let handler: (Data) -> Void = { _ in }
        busy.onData = handler
        XCTAssertThrowsError(try detect(busy))
        XCTAssertNotNil(busy.onData)
        XCTAssertFalse(busy.ownsQuery)
        XCTAssertTrue(busy.packets.isEmpty)
    }

    func testProtocolOnlyConfigAndCLISelectCodecWithoutIdentityOrQuery() throws {
        for family in TimeboxProtocolFamily.allCases {
            let h = CommandHarness(); h.detectedModels = []
            h.configuration = .init(defaultName: "speaker", devices: ["speaker": .init(mac: address, protocolFamily: family)])
            XCTAssertEqual(h.run(["brightness","20","--json"]), 0, h.stderr.joined())
            XCTAssertEqual(h.transport.packets, [Data([1,4,0,0x74,20,0x8C,0,2])])
            XCTAssertEqual(h.transport.connections.count, 1)
            XCTAssertTrue(h.rawStdout.contains("\"model\":null"))
            XCTAssertTrue(h.rawStdout.contains("\"protocol_family\":\"\(family.rawValue)\""))
            XCTAssertTrue(h.rawStdout.contains("\"protocol_source\":\"config\""))
        }
        let explicit = CommandHarness(); explicit.detectedModels = []
        XCTAssertEqual(explicit.run(["image","docs/validation/fixtures/evo-orientation.png","--address",address,"--protocol","legacy11","--json"]), 0, explicit.stderr.joined())
        XCTAssertTrue(explicit.rawStdout.contains("\"width\":11"))
        XCTAssertTrue(explicit.rawStdout.contains("\"protocol_source\":\"explicit\""))
        XCTAssertEqual(explicit.transport.connections.count, 1)
    }

    func testAutomaticStatusReusesProbeSnapshotAndKeepsProductUnknown() throws {
        for (data, family) in [(evo, TimeboxProtocolFamily.evo16), (legacy, .legacy11)] {
            let h = CommandHarness(); h.detectedModels = []; h.useProtocolProbe = true
            h.transport.replyChunks = [try frame(data, legacy: family == .legacy11)]
            XCTAssertEqual(h.run(["status","--address",address,"--json"]), 0, h.stderr.joined())
            XCTAssertEqual(h.transport.packets, [request])
            XCTAssertEqual(h.transport.connections.count, 1)
            XCTAssertTrue(h.rawStdout.contains("\"model\":null"))
            XCTAssertTrue(h.rawStdout.contains("\"protocol_source\":\"detected\""))
            XCTAssertTrue(h.rawStdout.contains("protocol_query_ms"))
            XCTAssertFalse(h.rawStdout.contains("model_source"))
        }
    }

    func testAutomaticImageUsesDetectedDimensionsAndFailedProbeNeverSendsImage() throws {
        for (data, family) in [(evo, TimeboxProtocolFamily.evo16), (legacy, .legacy11)] {
            let h = CommandHarness(); h.detectedModels = []; h.useProtocolProbe = true
            h.transport.replyChunks = [try frame(data, legacy: family == .legacy11)]
            XCTAssertEqual(h.run(["image","docs/validation/fixtures/evo-orientation.png","--address",address,"--json"]), 0, h.stderr.joined())
            XCTAssertEqual(h.transport.packets.count, 2)
            XCTAssertEqual(h.transport.packets[0], request)
            XCTAssertEqual(h.transport.connections.count, 2)
            XCTAssertTrue(h.rawStdout.contains("\"width\":\(family.width)"))
            XCTAssertTrue(h.rawStdout.contains("\"model\":null"))
        }
        let failed = CommandHarness(); failed.detectedModels = []; failed.useProtocolProbe = true
        failed.transport.replyChunks = [try frame(legacy + Data([0]), legacy: true)]
        XCTAssertEqual(failed.run(["image","docs/validation/fixtures/evo-orientation.png","--address",address,"--json"]), 1)
        XCTAssertEqual(failed.transport.packets, [request])
        XCTAssertTrue(failed.rawStdout.contains("unknown_protocol"))
        XCTAssertFalse(failed.transport.isConnected)
    }

    func testProtocolAutoBypassesConfigAndConflictingModelsFailBeforeControlWrite() throws {
        let h = CommandHarness(); h.useProtocolProbe = true
        h.configuration = .init(defaultName: "speaker", devices: ["speaker": .init(mac: address, protocolFamily: .legacy11)])
        h.transport.replyChunks = [try frame(evo, legacy: false)]
        XCTAssertEqual(h.run(["status","--protocol","auto","--json"]), 0, h.stderr.joined())
        XCTAssertTrue(h.rawStdout.contains("\"protocol_family\":\"evo16\""))
        let conflict = CommandHarness()
        conflict.configuration = .init(defaultName: "speaker", devices: ["speaker": .init(mac: address, model: .evo)])
        XCTAssertEqual(conflict.run(["brightness","20","--protocol","legacy11","--json"]), 1)
        XCTAssertTrue(conflict.rawStdout.contains("conflicting_protocol"))
        XCTAssertTrue(conflict.transport.packets.isEmpty)
        XCTAssertEqual(conflict.run(["brightness","20","--protocol","legacy11","--model","auto"]), 0)
    }

    func testREPLCachesFamilyButFreshStatusAndTargetSwitchUseTheirOwnProtocol() throws {
        let h = CommandHarness(); h.detectedModels = []; h.useProtocolProbe = true
        h.configuration = .init(defaultName: "classic", devices: [
            "classic": .init(mac: address), "evo": .init(mac: "AA:BB:CC:DD:EE:02", protocolFamily: .evo16)])
        var fresh = legacy; fresh[8] = 42
        h.transport.replyChunks = [try frame(legacy, legacy: true), try frame(fresh, legacy: true)]
        h.input = ["brightness 20", "status", "target", "target evo", "brightness 20", "target", "quit"]
        XCTAssertEqual(h.run(["repl"]), 0, h.stderr.joined())
        XCTAssertTrue(h.stderr.isEmpty)
        XCTAssertEqual(h.transport.packets.count, 4) // detection, legacy write, fresh read, Evo write
        XCTAssertEqual(h.transport.packets[0], request)
        XCTAssertEqual(h.transport.packets[2], Data([1,3,6,0,0x46,0x49,0,2]))
        XCTAssertTrue(h.stdout.joined().contains("system brightness: 42%"))
        XCTAssertTrue(h.stdout.joined().contains("protocol: legacy11 (detected)"))
        XCTAssertTrue(h.stdout.joined().contains("protocol: evo16 (config)"))
        XCTAssertEqual(h.transport.writeTargets.last, "AA:BB:CC:DD:EE:02")
    }

    func testConfigValidationAndSourceEditsKeepProtocolCommentsAndUnknownFields() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = "# devices\ndefault: speaker\ndevices:\n  speaker:\n    mac: \(address)\n    protocol: legacy11 # shared\n    custom: preserved\n"
        try Data(text.utf8).write(to: url)
        let file = DeviceConfigFile(url: url)
        XCTAssertEqual(try file.read().configuration.devices["speaker"]?.protocolFamily, .legacy11)
        _ = try file.saveDiscovered([TimeboxDevice(name: "Timebox", address: address, isPaired: true, isConnected: false, source: .bluetooth)])
        _ = try file.rename("speaker", to: "classic")
        let saved = try file.read()
        XCTAssertEqual(saved.configuration.devices["classic"]?.protocolFamily, .legacy11)
        XCTAssertTrue(saved.text.contains("protocol: legacy11 # shared"))
        XCTAssertTrue(saved.text.contains("custom: preserved"))
        for field in ["protocol: unknown", "protocol: [legacy11]", "model: evo\n    protocol: legacy11"] {
            XCTAssertThrowsError(try DeviceConfigDocumentForTest.parse("devices:\n  speaker:\n    mac: \(address)\n    \(field)\n", at: url))
        }
    }

    func testProtocolOptionsAreRejectedOutsideDeviceCommandsAndInsideREPL() {
        for arguments in [["list"], ["config"], ["device", "select", "speaker"]] {
            let h = CommandHarness()
            XCTAssertEqual(h.run(arguments + ["--protocol", "legacy11"]), 2)
            XCTAssertTrue(h.transport.connections.isEmpty)
        }
        let h = CommandHarness(); h.input = ["brightness 20 --protocol legacy11", "quit"]
        XCTAssertEqual(h.run(["repl", "--address", address]), 0)
        XCTAssertTrue(h.transport.packets.isEmpty)
        let raw = CommandHarness(); raw.detectedModels = []
        XCTAssertEqual(raw.run(["send-hex","01","--address",address]), 0)
        XCTAssertEqual(raw.transport.packets, [Data([1])])
    }
}

private enum DeviceConfigDocumentForTest {
    static func parse(_ text: String, at url: URL) throws -> DeviceConfigDocument {
        try Data(text.utf8).write(to: url)
        return try DeviceConfigFile(url: url).read()
    }
}
