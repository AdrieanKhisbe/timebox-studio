import XCTest
import TimeboxKit
@testable import TimeboxBluetooth

final class MiniBluetoothPromotionTests: XCTestCase {
    // Parent AKTBR capture: 3 disabled ten-byte records, preserving all opaque fields.
    private let baseline = Data([0,0,0,0,0,0,1,0,0,50, 1,0,0,0,0,0,1,0,0,50, 2,0,0,0,0,0,1,0,0,50])
    private let captured = "01 23 00 04 42 55 00 00 00 00 00 00 03 04 00 00 32 03 04 00 00 00 00 00 03 04 00 00 32 03 05 00 00 00 00 00 03 04 00 00 32 5a 03 04 02"
    private let greeting = Data([0,5,0x48,0x45,0x4c,0x4c,0x4f,0])
    private func bytes(_ hex: String) -> Data { Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! }) }

    func testMiniAlarmReaderUsesModelDialectAcrossFragmentedGreetingAndCapturedEscapes() throws {
        let connection = QueryConnection()
        connection.chunks = (greeting + bytes(captured)).map { Data([$0]) }
        let records = try TimeboxAlarmReader.read(from: connection, model: .mini)
        XCTAssertEqual(records.map(\.slot), [0,1,2])
        XCTAssertEqual(try records.reduce(Data()) { $0 + (try $1.recordBytes) }, baseline)
        XCTAssertEqual(connection.request, Data([1,3,6,0,0x42,0x45,0,2]))
        XCTAssertFalse(connection.isConnected)
        XCTAssertFalse(connection.access.queryInProgress)
        XCTAssertNil(connection.onData)
    }

    func testGenericMiniQueryPropagatesDialectAndKeepsReservedResponseBytes() throws {
        let query = try TimeboxQuery<Data>(payload: Data([0x7e]), responseCommand: 0x7e, model: .mini) { $0 }
        let frame = try TimeboxMiniEncoder.frame(Data([4,0x7e,0x55,1,2,3]))
        let connection = QueryConnection()
        connection.chunks = [greeting.prefix(3), Data(greeting.dropFirst(3)) + frame.prefix(4), Data(frame.dropFirst(4))]
        XCTAssertEqual(try TimeboxQueryReader.read(query, from: connection), Data([1,2,3]))
        XCTAssertFalse(connection.isConnected)
        XCTAssertNil(connection.onData)
    }

    func testMiniQueryGreetingDoesNotCompleteRequestAndErrorsReleaseOwnership() throws {
        for (wire, expected) in [(greeting, TimeboxQueryError.timeout),
                                 (Data(greeting.prefix(3)), .invalidResponse("truncated frame before timeout"))] {
            let connection = QueryConnection(); connection.chunks = [wire]
            XCTAssertThrowsError(try TimeboxAlarmReader.read(from: connection, model: .mini, timeout: 0.001)) {
                XCTAssertEqual($0 as? TimeboxQueryError, expected)
            }
            XCTAssertFalse(connection.isConnected); XCTAssertNil(connection.onData)
            XCTAssertFalse(connection.access.queryInProgress)
        }
        let bad = QueryConnection(); bad.chunks = [Data([0,5,0x48,0x45,0x4c,0x4c,0x58,0])]
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: bad, model: .mini)) {
            guard case .invalidResponse = $0 as? TimeboxQueryError else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(bad.isConnected); XCTAssertFalse(bad.access.queryInProgress)
        let cancelled = QueryConnection()
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: cancelled, model: .mini, isCancelled: { true })) {
            XCTAssertEqual($0 as? TimeboxQueryError, .cancelled)
        }
        XCTAssertNil(cancelled.request); XCTAssertFalse(cancelled.isConnected)
        let busy = QueryConnection(); busy.onData = { _ in }
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: busy, model: .mini)) {
            XCTAssertEqual($0 as? TimeboxQueryError, .busy)
        }
        XCTAssertTrue(busy.isConnected); XCTAssertNotNil(busy.onData)
    }

    func testMiniBareClockWriterUsesOneWriteConnectionWithoutQuery() throws {
        let transport = MiniPromotionTransport()
        var factories = 0
        let result = try TimeboxDisplayWriter.perform(.clock(), device: .mock, channel: 4, model: .mini,
            makeTransport: { factories += 1; return transport })
        XCTAssertEqual(factories, 1)
        XCTAssertEqual(result.packetCount, 1)
        XCTAssertEqual(transport.controls, [bytes("01 05 00 45 00 03 04 4b 00 02")])
        XCTAssertEqual(result.byteCount, 10)
        XCTAssertEqual(transport.channel, 4)
        XCTAssertTrue(transport.queries.isEmpty)
        XCTAssertFalse(transport.isConnected)
    }

    func testMiniUnsupportedDisplayProfilesRemainBlockedBeforeAnyTransport() throws {
        var factories = 0
        for selection: TimeboxDisplay in [.clock(style: .fullScreen), .design(), .design(index:1), .effects()] {
            XCTAssertThrowsError(try TimeboxDisplayWriter.perform(selection, device: .mock, model: .mini,
                makeTransport: { factories += 1; return MiniPromotionTransport() })) {
                guard case .unsupported = $0 as? TimeboxModelError else { return XCTFail("\($0)") }
            }
        }
        XCTAssertEqual(factories, 0)
    }

    @MainActor
    func testMiniClientSendsPromotedClockStopwatchAndFullAlarmRecordsWithoutQueries() async throws {
        let transport = MiniPromotionTransport()
        var factories = 0
        let client = TimeboxClient(model: .mini, transport: transport,
            displayTransportFactory: { factories += 1; return MiniPromotionTransport() })
        try await client.connect(to: .mock)
        try await client.display(.clock())
        try await client.stopwatch(.start)
        try await client.stopwatch(.stop)
        try await client.stopwatch(.reset)
        let current = try TimeboxAlarmDecoder.decode(baseline, model: .mini)[2]
        try await client.setAlarm(current, schedule: TimeboxAlarmSchedule(hour: 2, minute: 52))
        try await client.disableAlarm(current)
        XCTAssertEqual(transport.controls, [
            bytes("01 05 00 45 00 03 04 4b 00 02"),
            bytes("01 05 00 45 06 03 04 51 00 02"),
            bytes("01 05 00 45 06 00 50 00 02"),
            bytes("01 05 00 45 06 03 05 52 00 02"),
            bytes("01 0d 00 43 03 05 03 04 03 05 34 00 00 03 04 00 00 32 bc 00 02"),
            bytes("01 0d 00 43 03 05 00 00 00 00 00 03 04 00 00 32 85 00 02")
        ])
        XCTAssertEqual(factories, 0); XCTAssertTrue(transport.queries.isEmpty)
        XCTAssertEqual(transport.connects, 1); XCTAssertTrue(client.isConnected)
        // A promoted operation's write errors still propagate unchanged.
        transport.writeError = TimeboxTransportError.notConnected
        do { try await client.stopwatch(.start); XCTFail("Expected write failure") }
        catch { XCTAssertEqual(error as? TimeboxTransportError, .notConnected) }
        client.disconnect()
    }

    func testEvoBareClockStillRequiresFreshProfileAndSeparateControlConnection() throws {
        let raw = Data([0,0,0,52,18,64,100,0,1,0,100,1,255,0,0,2,1,0,0,0])
        let response = try TimeboxPacketEncoder.encodePayload(Data([4,0x46,0x55]) + raw)
        var connections: [MiniPromotionTransport] = []
        let result = try TimeboxDisplayWriter.perform(.clock(), device: .mock, model: .evo, makeTransport: {
            let transport = MiniPromotionTransport()
            if connections.isEmpty { transport.replies = [response] }
            connections.append(transport); return transport
        })
        XCTAssertEqual(result.packetCount, 1); XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(connections[0].queries, [Data([1,3,0,0x46,0x49,0,2])])
        XCTAssertTrue(connections[0].controls.isEmpty)
        let expected = try TimeboxDisplayProfile(channel: .clock, status: TimeboxStatusDecoder.decode(raw))
        XCTAssertEqual(connections[1].controls, [try TimeboxPacketEncoder.encode(.displayProfile(expected))])
        XCTAssertTrue(connections.allSatisfy { !$0.isConnected })
    }
}

private final class MiniPromotionTransport: TimeboxTransport, TimeboxDisplayTransport {
    var isConnected = false
    var onConnectionChange: ((Bool) -> Void)?
    var onData: ((Data) -> Void)?
    var channel: UInt8?
    var controls: [Data] = []
    var queries: [Data] = []
    var replies: [Data] = []
    var writeError: Error?
    var connects = 0
    private var access = TimeboxQueryAccess()
    func connect(to device: TimeboxDevice) async throws { connects += 1; isConnected = true; access.didConnect() }
    func disconnect() { isConnected = false }
    func write(_ data: Data) async throws { try send(data) }
    func connectForDisplay(to device: TimeboxDevice, channel: UInt8?) throws {
        connects += 1; isConnected = true; self.channel = channel; access.didConnect()
    }
    func writeDisplay(_ data: Data) throws { try send(data) }
    private func send(_ data: Data) throws {
        if let writeError { throw writeError }; controls.append(data)
    }
    func settleDisplay(milliseconds: Int) {}
    func beginQuery() throws { try access.beginQuery(isConnected: isConnected, hasReceiveHandler: onData != nil) }
    func endQuery() { access.endQuery() }
    func writeQuery(_ data: Data) throws {
        try access.beginWrite(isQuery: true); defer { access.endWrite() }; queries.append(data)
    }
    func waitForQuery(milliseconds: Int) {
        if !replies.isEmpty { onData?(replies.removeFirst()) }
    }
}
