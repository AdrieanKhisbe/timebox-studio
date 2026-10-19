import XCTest
import TimeboxKit
@testable import TimeboxBluetooth
import TimeboxCLIKit

final class DisplayCapabilitiesTests: XCTestCase {
    private let device = TimeboxDevice(name: "selected", address: "AA:BB:CC:DD:EE:01", isPaired: true, isConnected: false, source: .bluetooth)
    // Actual parent status data, captured before explicit clock/profile replacement.
    private let raw: [UInt8] = [0, 0, 0, 52, 18, 64, 100, 0, 1, 0, 100, 1, 255, 0, 0, 2, 1, 0, 0, 0]
    private func response(_ command: UInt8, _ payload: [UInt8]) throws -> Data {
        try TimeboxPacketEncoder.encodePayload(Data([4, command, 0x55] + payload))
    }

    func testCapabilityQueryIgnoresOtherBDSelectorsAndRetainsStrictMatchingSchema() throws {
        let query = TimeboxQuery<TimeboxDesignCapabilities>.designCapabilities
        XCTAssertEqual(query.request, Data([1, 4, 0, 0xBD, 0x18, 0xD9, 0, 2]))
        let wire = try response(0xBD, [0x17, 2]) + response(0xBD, [0x18, 1])
        let connection = QueryConnection(); connection.chunks = [Data(wire.prefix(4)), Data(wire.dropFirst(4))]
        XCTAssertTrue(try TimeboxQueryReader.read(query, from: connection).supportsThreeTabs)
        let separate = QueryConnection()
        separate.chunks = [try response(0xBD, [0x17, 0]), try response(0xBD, [0x18, 1])]
        XCTAssertEqual(try TimeboxQueryReader.read(query, from: separate).rawFlag, 1)
        for malformed: [UInt8] in [[], [0x18], [0x18, 1, 0]] {
            let bad = QueryConnection(); bad.chunks = [try response(0xBD, malformed)]
            XCTAssertThrowsError(try TimeboxQueryReader.read(query, from: bad, timeout: 0.001)) {
                guard case .invalidResponse = $0 as? TimeboxQueryError else { return XCTFail("\($0)") }
            }
            XCTAssertFalse(bad.isConnected)
        }
        let wrong = QueryConnection(); wrong.chunks = [try response(0xBD, [0x17, 1])]
        XCTAssertThrowsError(try TimeboxQueryReader.read(query, from: wrong, timeout: 0.001)) {
            XCTAssertEqual($0 as? TimeboxQueryError, .timeout)
        }
    }

    func testLegacyEffectsFailBeforeQueryConnectionOrControlWrites() throws {
        for selection: TimeboxDisplay in [.effects(), .effects(effect: .sparkles), .effects(effect: .fire)] {
            let factory = DisplayConnectionFactory()
            XCTAssertThrowsError(try TimeboxDisplayWriter.perform(selection, device: device, makeTransport: factory.make))
            XCTAssertTrue(factory.connections.isEmpty)
        }
        let repl = CommandHarness()
        repl.input = ["effect 9", "display effects", "quit"]
        XCTAssertEqual(repl.run(["repl", "--address", "AA:BB:CC:DD:EE:01"]), 0)
        XCTAssertTrue(repl.transport.packets.isEmpty)
    }

    func testStoredProfileMappingPreservesValuesWithoutGuessedDefaults() throws {
        let status = try TimeboxStatusDecoder.decode(Data(raw))
        let clock = try TimeboxDisplayProfile(channel: .clock, status: status)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.displayProfile(clock)),
                       Data([1, 13, 0, 0x45, 0, 1, 2, 1, 0, 0, 0, 255, 0, 0, 0x55, 1, 2]))
        let light = try TimeboxDisplayProfile(channel: .light, status: status)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.displayProfile(light)),
                       try TimeboxPacketEncoder.encodePayload(Data([0x45, 1, 52, 18, 64, 100, 0, 1, 0, 0, 0])))
        var unknown = raw
        unknown[0] = 0xFE; unknown[15] = 0xCA; unknown[2] = 0xA7; unknown[7] = 0xB2
        let unknownStatus = try TimeboxStatusDecoder.decode(Data(unknown))
        let unknownClock = try TimeboxDisplayProfile(channel: .clock, status: unknownStatus)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.displayProfile(unknownClock))[6], 0xCA)
        let unknownLight = try TimeboxDisplayProfile(channel: .light, status: unknownStatus)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.displayProfile(unknownLight))[9], 0xB2)
        // Invalid flags are specific to the requested profile; unknown current mode
        // and unrelated flags do not freeze a separately known clock profile.
        unknown[8] = 2
        let invalidLight = try TimeboxStatusDecoder.decode(Data(unknown))
        XCTAssertThrowsError(try TimeboxDisplayProfile(channel: .light, status: invalidLight))
        XCTAssertNoThrow(try TimeboxDisplayProfile(channel: .clock, status: invalidLight))
        for index in [11, 16, 17, 18, 19] {
            var flags = raw; flags[index] = 2
            XCTAssertThrowsError(try TimeboxDisplayProfile(channel: .clock, status: TimeboxStatusDecoder.decode(Data(flags))))
        }
        let extended = try TimeboxStatusDecoder.decode(Data(raw + [0x91]))
        XCTAssertThrowsError(try TimeboxDisplayProfile(channel: .clock, status: extended))
    }

    func testFreshCapabilityMustPrecedeEveryChannelAndTabWrite() throws {
        for index in 0...2 {
            let factory = DisplayConnectionFactory()
            factory.queryChunks = [try response(0xBD, [0x17, 0]) + response(0xBD, [0x18, 1])]
            let result = try TimeboxDisplayWriter.perform(.design(index: index), device: device, channel: 7, makeTransport: factory.make)
            XCTAssertEqual(result.packetCount, 2)
            XCTAssertEqual(factory.connections.count, 2)
            XCTAssertEqual(factory.connections[0].queries, [Data([1, 4, 0, 0xBD, 0x18, 0xD9, 0, 2])])
            XCTAssertTrue(factory.connections[0].controls.isEmpty)
            XCTAssertEqual(factory.connections[1].controls, [Data([1, 4, 0, 0x45, 5, 0x4E, 0, 2]),
                Data([1, 5, 0, 0xBD, 0x17, UInt8(index), UInt8(0xD9 + index), 0, 2])])
            XCTAssertTrue(factory.connections.allSatisfy { $0.channel == 7 && $0.address == device.address && !$0.isConnected })
        }
    }

    func testFalseUnknownMalformedAndTimedOutCapabilitiesSendNoControlPackets() throws {
        for payload: [UInt8]? in [[0x18, 0], [0x18, 2], [0x18], [0x17, 1], nil] {
            let factory = DisplayConnectionFactory()
            factory.queryChunks = try payload.map { [try response(0xBD, $0)] } ?? []
            XCTAssertThrowsError(try TimeboxDisplayWriter.perform(.design(index: 1), device: device,
                timeout: 0.001, makeTransport: factory.make))
            XCTAssertEqual(factory.connections.count, 1)
            XCTAssertTrue(factory.connections[0].controls.isEmpty)
            XCTAssertFalse(factory.connections[0].isConnected)
        }
        for invalid in [-1, 3, Int.max] {
            let factory = DisplayConnectionFactory()
            XCTAssertThrowsError(try TimeboxDisplayWriter.perform(.design(index: invalid), device: device, makeTransport: factory.make))
            XCTAssertTrue(factory.connections.isEmpty)
        }
    }

    func testPreservingWriterReadsFreshProfilesRejectsExtensionsAndReportsPartialTransmission() throws {
        for selection: TimeboxDisplay in [.clock(), .light()] {
            let factory = DisplayConnectionFactory(); factory.queryChunks = [try response(0x46, raw)]
            let result = try TimeboxDisplayWriter.perform(selection, device: device, makeTransport: factory.make)
            XCTAssertEqual(result.packetCount, 1)
            XCTAssertEqual(factory.connections[0].queries, [Data([1, 3, 0, 0x46, 0x49, 0, 2])])
            XCTAssertEqual(factory.connections.count, 2)
            let expected = try TimeboxDisplayProfile(channel: XCTUnwrap(selection.preservedChannel), status: TimeboxStatusDecoder.decode(Data(raw)))
            XCTAssertEqual(factory.connections[1].controls, [try TimeboxPacketEncoder.encode(.displayProfile(expected))])
        }
        let extensionFactory = DisplayConnectionFactory(); extensionFactory.queryChunks = [try response(0x46, raw + [0xFA])]
        XCTAssertThrowsError(try TimeboxDisplayWriter.perform(.light(), device: device, makeTransport: extensionFactory.make))
        XCTAssertEqual(extensionFactory.connections.count, 1)
        let partial = DisplayConnectionFactory(); partial.queryChunks = [try response(0xBD, [0x18, 1])]; partial.failSecondControl = true
        XCTAssertThrowsError(try TimeboxDisplayWriter.perform(.design(index: 1), device: device, makeTransport: partial.make)) { error in
            guard case .incompleteWrite(sent: 1, total: 2, _) = error as? TimeboxDisplayError else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(partial.connections[1].isConnected)
    }

    func testCLIAndREPLRunFreshPreparationAndReopenTheSelectedTarget() throws {
        for format in ["--json", "--yaml"] {
            let cli = CommandHarness(); cli.transport.replyChunks = [try response(0x46, raw)]
            XCTAssertEqual(cli.run(["display", "clock", "--address", device.address, format]), 0, cli.stderr.joined())
            XCTAssertEqual(cli.transport.packets.count, 2)
            XCTAssertTrue(cli.rawStdout.contains("preserved_profile"))
        }
        let repl = CommandHarness()
        repl.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: device.address)])
        repl.transport.replyChunks = [try response(0xBD, [0x17, 2]) + response(0xBD, [0x18, 1])]
        repl.input = ["design 1", "brightness 50", "quit"]
        XCTAssertEqual(repl.run(["repl", "--channel", "7"]), 0, repl.stderr.joined())
        XCTAssertEqual(repl.transport.packets.map { $0[3] }, [0xBD, 0x45, 0xBD, 0x74])
        XCTAssertTrue(repl.transport.connections.allSatisfy { $0.0 == device.address && $0.1 == 7 })
        let failed = CommandHarness(); failed.transport.replyChunks = [try response(0xBD, [0x18, 0])]
        XCTAssertEqual(failed.run(["design", "1", "--address", device.address]), 1)
        XCTAssertEqual(failed.transport.packets.map { $0[3] }, [0xBD])
    }

    func testCancellationAndReadFailuresNeverFallThroughToControlWrites() throws {
        let canceled = DisplayConnectionFactory()
        XCTAssertThrowsError(try TimeboxDisplayWriter.perform(.design(index: 0), device: device,
            isCancelled: { true }, makeTransport: canceled.make)) {
            XCTAssertEqual($0 as? TimeboxQueryError, .cancelled)
        }
        XCTAssertTrue(canceled.connections.isEmpty)
        var afterReply = false
        let midRead = DisplayConnectionFactory()
        midRead.queryChunks = [try response(0xBD, [0x18, 1])]
        midRead.onReply = { afterReply = true }
        XCTAssertThrowsError(try TimeboxDisplayWriter.perform(.design(index: 0), device: device,
            isCancelled: { afterReply }, makeTransport: midRead.make)) {
            XCTAssertEqual($0 as? TimeboxQueryError, .cancelled)
        }
        XCTAssertEqual(midRead.connections.count, 1)
        XCTAssertTrue(midRead.connections[0].controls.isEmpty)
        for broken: [UInt8]? in [Array(raw.prefix(19)), raw + [0xFA], nil] {
            let factory = DisplayConnectionFactory()
            factory.queryChunks = try broken.map { [try response(0x46, $0)] } ?? []
            XCTAssertThrowsError(try TimeboxDisplayWriter.perform(.clock(), device: device,
                timeout: 0.001, makeTransport: factory.make))
            XCTAssertEqual(factory.connections.count, 1)
            XCTAssertTrue(factory.connections[0].controls.isEmpty)
        }
    }

    func testFailedREPLPreparationDoesNotResumeOrWriteToOldConnection() throws {
        let repl = CommandHarness()
        repl.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: device.address)])
        repl.transport.replyChunks = [try response(0xBD, [0x18, 0])]
        repl.input = ["design 1", "brightness 50", "quit"]
        XCTAssertEqual(repl.run(["repl"]), 0)
        XCTAssertEqual(repl.transport.packets.map { $0[3] }, [0xBD])
        XCTAssertTrue(repl.stderr.joined().contains("disconnected"))
        XCTAssertFalse(repl.transport.isConnected)
    }

    func testConnectedLibraryLifecycleReopensAfterSuccessAndStaysClosedAfterFailure() async throws {
        let factory = DisplayConnectionFactory(); factory.queryChunks = [try response(0x46, raw)]
        let persistent = DisplayPersistentTransport()
        let client = TimeboxClient(transport: persistent, displayTransportFactory: factory.make)
        try await client.connect(to: device, channel: 7)
        try await client.display(.clock())
        XCTAssertEqual(persistent.connections, 2)
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(factory.connections.count, 2)
        factory.queryChunks = [try response(0xBD, [0x18, 0])]
        factory.queryEveryConnection = true
        do { try await client.display(.design(index: 1)); XCTFail("Expected capability failure") }
        catch { XCTAssertEqual(error as? TimeboxDisplayError, .designCapability(0)) }
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(persistent.connections, 2)
        client.disconnect()
    }
}

private final class DisplayConnectionFactory {
    var connections: [DisplayIOConnection] = []
    var queryChunks: [Data] = []
    var failSecondControl = false
    var queryEveryConnection = false
    var onReply: (() -> Void)?
    func make() -> TimeboxDisplayTransport {
        let connection = DisplayIOConnection()
        connection.onReply = onReply
        if connections.isEmpty || queryEveryConnection { connection.chunks = queryChunks }
        if failSecondControl { connection.failControlAt = 2 }
        connections.append(connection)
        return connection
    }
}
private final class DisplayIOConnection: TimeboxDisplayTransport {
    var isConnected = false
    var onData: ((Data) -> Void)?
    var chunks: [Data] = []
    var queries: [Data] = [], controls: [Data] = []
    var channel: UInt8?, address: String?
    var failControlAt: Int?
    var onReply: (() -> Void)?
    var access = TimeboxQueryAccess()
    func connectForDisplay(to device: TimeboxDevice, channel: UInt8?) throws {
        address = device.address; self.channel = channel; isConnected = true; access.didConnect()
    }
    func beginQuery() throws { try access.beginQuery(isConnected: isConnected, hasReceiveHandler: onData != nil) }
    func endQuery() { access.endQuery() }
    func writeQuery(_ data: Data) throws { try access.beginWrite(isQuery: true); defer { access.endWrite() }; queries.append(data) }
    func writeDisplay(_ data: Data) throws {
        try access.beginWrite(); defer { access.endWrite() }
        if controls.count + 1 == failControlAt { throw TimeboxTransportError.notConnected }
        controls.append(data)
    }
    func waitForQuery(milliseconds: Int) { if !chunks.isEmpty { onData?(chunks.removeFirst()); onReply?() } }
    func settleDisplay(milliseconds: Int) {}
    func disconnect() { isConnected = false }
}
private final class DisplayPersistentTransport: TimeboxTransport {
    var isConnected = false
    var onConnectionChange: ((Bool) -> Void)?
    var connections = 0
    func connect(to device: TimeboxDevice) async throws { connections += 1; isConnected = true }
    func disconnect() { isConnected = false }
    func write(_ data: Data) async throws {}
}
