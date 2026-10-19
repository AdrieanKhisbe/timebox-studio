import XCTest
@testable import TimeboxBluetooth
import TimeboxKit
import TimeboxUtilities

final class QueryConnection: TimeboxQueryTransport {
    var isConnected = true
    var onData: ((Data) -> Void)?
    var chunks: [Data] = []
    var request: Data?
    var disconnectOnWait = false
    var waited = false
    var access = TimeboxQueryAccess()
    var writeError: Error?
    var onWrite: (() -> Void)?
    var onWait: (() -> Void)?
    func beginQuery() throws { try access.beginQuery(isConnected: isConnected, hasReceiveHandler: onData != nil) }
    func endQuery() { access.endQuery() }
    func writeQuery(_ data: Data) throws {
        try access.beginWrite(isQuery: true)
        defer { access.endWrite() }
        if let writeError { throw writeError }
        request = data
        onWrite?()
    }
    func waitForQuery(milliseconds: Int) {
        waited = true
        onWait?()
        if disconnectOnWait { isConnected = false }
        if !chunks.isEmpty { onData?(chunks.removeFirst()) }
    }
    func disconnect() { isConnected = false }
}

final class AlarmQueryTests: XCTestCase {
    static func capturedFrame() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/validation/fixtures/evo-alarm-list-live.json"))) as! [String: Any]
        return try HexStringParser.data(from: fixture["response"] as! String)
    }

    func testLiveFixtureFragmentationUnrelatedAndDuplicateReplies() throws {
        let frame = try Self.capturedFrame()
        let connection = QueryConnection()
        let unrelated = Data([1, 6, 0, 4, 0x45, 0x55, 1, 0xA5, 0, 2])
        connection.chunks = [unrelated + frame.prefix(3), Data(frame.dropFirst(3).prefix(30)), Data(frame.dropFirst(33)) + frame]
        let alarms = try TimeboxAlarmReader.read(from: connection)
        XCTAssertEqual(alarms.count, 10)
        XCTAssertEqual(alarms[0].hour, 10)
        XCTAssertEqual(alarms[0].weekdays, ["wed"])
        XCTAssertEqual(connection.request, Data([1, 3, 0, 0x42, 0x45, 0, 2]))
        XCTAssertFalse(connection.isConnected)
        XCTAssertNil(connection.onData)
    }

    func testTimeoutDisconnectionCancellationCorruptionAndStaleRepliesAreErrors() throws {
        let quiet = QueryConnection()
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: quiet, timeout: 0.01)) { XCTAssertEqual($0 as? TimeboxQueryError, .timeout) }
        XCTAssertFalse(quiet.isConnected)
        quiet.onData?(try Self.capturedFrame()) // Late bytes cannot complete another query.
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: quiet)) { XCTAssertEqual($0 as? TimeboxQueryError, .disconnected) }
        let lost = QueryConnection(); lost.disconnectOnWait = true
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: lost)) { XCTAssertEqual($0 as? TimeboxQueryError, .disconnected) }
        let cancelled = QueryConnection()
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: cancelled, isCancelled: { cancelled.waited })) { XCTAssertEqual($0 as? TimeboxQueryError, .cancelled) }
        XCTAssertFalse(cancelled.isConnected)
        var bad = try Self.capturedFrame(); bad[bad.count - 2] ^= 1
        let corrupt = QueryConnection(); corrupt.chunks = [bad]
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: corrupt)) { error in
            guard case .invalidResponse = error as? TimeboxQueryError else { return XCTFail("\(error)") }
        }
        let truncated = QueryConnection(); truncated.chunks = [Data(bad.prefix(5))]
        XCTAssertThrowsError(try TimeboxAlarmReader.read(from: truncated, timeout: 0.01)) { error in
            guard case .invalidResponse = error as? TimeboxQueryError else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(truncated.isConnected)
    }
}
