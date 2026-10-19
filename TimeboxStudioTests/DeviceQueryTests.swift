import XCTest
@testable import TimeboxBluetooth
import TimeboxKit

final class DeviceQueryTests: XCTestCase {
    func testGenericQueryRetainsTypedDecodingAndRejectsMalformedSchema() throws {
        // This envelope is synthetic; no settings opcode or schema is claimed.
        let query = try TimeboxQuery<Int>(payload: Data([0x42]), responseCommand: 0x42) { data in
            try TimeboxAlarmDecoder.decode(data).filter(\.enabled).count
        }
        XCTAssertEqual(query.request, Data([1, 3, 0, 0x42, 0x45, 0, 2]))
        let connection = QueryConnection()
        connection.chunks = [try AlarmQueryTests.capturedFrame()]
        XCTAssertEqual(try TimeboxQueryReader.read(query, from: connection), 1)
        let malformed = QueryConnection()
        malformed.chunks = [try TimeboxPacketEncoder.encodePayload(Data([4, 0x42, 0x55, 1]))]
        XCTAssertThrowsError(try TimeboxQueryReader.read(query, from: malformed)) {
            guard case .invalidResponse = $0 as? TimeboxQueryError else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(malformed.isConnected)
        XCTAssertFalse(malformed.access.queryInProgress)
    }

    func testQueryRejectsNestedQueriesAndWritesWhilePumping() throws {
        let connection = QueryConnection()
        connection.chunks = [try AlarmQueryTests.capturedFrame()]
        var attempted = false
        connection.onWait = {
            attempted = true
            do { _ = try TimeboxQueryReader.read(TimeboxQuery<[TimeboxAlarm]>.alarms, from: connection); XCTFail("Nested query accepted") }
            catch { XCTAssertEqual(error as? TimeboxQueryError, .busy) }
            do { try connection.writeQuery(Data([0x42])); XCTFail("Second request accepted") }
            catch { XCTAssertEqual(error as? TimeboxQueryError, .busy) }
            do { try connection.access.beginWrite(); XCTFail("Interleaved write accepted") }
            catch { XCTAssertEqual(error as? TimeboxQueryError, .busy) }
            XCTAssertTrue(connection.isConnected)
        }
        XCTAssertEqual(try TimeboxQueryReader.read(.alarms, from: connection).count, 10)
        XCTAssertTrue(attempted)
    }

    func testLateIdenticalReplyCannotCompleteQueryOnFreshLink() throws {
        let old = QueryConnection()
        var lateHandler: ((Data) -> Void)?
        old.onWait = { lateHandler = old.onData }
        XCTAssertThrowsError(try TimeboxQueryReader.read(.alarms, from: old, timeout: 0.001))
        XCTAssertFalse(old.isConnected)
        let fresh = QueryConnection()
        let frame = try AlarmQueryTests.capturedFrame()
        fresh.onWait = { lateHandler?(frame) }
        // Injecting an old callback does not deliver to the new reader.
        XCTAssertThrowsError(try TimeboxQueryReader.read(.alarms, from: fresh, timeout: 0.001)) {
            XCTAssertEqual($0 as? TimeboxQueryError, .timeout)
        }
        XCTAssertFalse(fresh.isConnected)
    }

    func testCancellationBeforeSendingWriteFailureAndExistingHandlerCleanup() throws {
        let cancelled = QueryConnection()
        XCTAssertThrowsError(try TimeboxQueryReader.read(.alarms, from: cancelled, isCancelled: { true })) {
            XCTAssertEqual($0 as? TimeboxQueryError, .cancelled)
        }
        XCTAssertNil(cancelled.request)
        XCTAssertFalse(cancelled.isConnected)
        XCTAssertFalse(cancelled.access.queryInProgress)
        let failed = QueryConnection()
        failed.writeError = TimeboxTransportError.notConnected
        XCTAssertThrowsError(try TimeboxQueryReader.read(.alarms, from: failed)) {
            XCTAssertEqual($0 as? TimeboxTransportError, .notConnected)
        }
        XCTAssertNil(failed.onData)
        XCTAssertFalse(failed.isConnected)
        let busy = QueryConnection()
        var received = false
        busy.onData = { _ in received = true }
        XCTAssertThrowsError(try TimeboxQueryReader.read(.alarms, from: busy)) {
            XCTAssertEqual($0 as? TimeboxQueryError, .busy)
        }
        busy.onData?(Data())
        XCTAssertTrue(received)
        XCTAssertTrue(busy.isConnected)
    }

    func testFreshLinkRequiredAfterEveryQueryOrEarlierWrite() throws {
        var access = TimeboxQueryAccess()
        try access.beginWrite()
        XCTAssertThrowsError(try access.beginQuery(isConnected: true, hasReceiveHandler: false))
        access.endWrite()
        // Even completed prior traffic disqualifies a link from a fresh query.
        XCTAssertThrowsError(try access.beginQuery(isConnected: true, hasReceiveHandler: false))
        access.didConnect()
        try access.beginQuery(isConnected: true, hasReceiveHandler: false)
        try access.beginWrite(isQuery: true)
        access.endWrite()
        XCTAssertThrowsError(try access.beginWrite(isQuery: true))
        XCTAssertThrowsError(try access.beginWrite())
        access.endQuery()
        XCTAssertThrowsError(try access.beginQuery(isConnected: true, hasReceiveHandler: false))
        access.didConnect()
        try access.beginQuery(isConnected: true, hasReceiveHandler: false)
        access.endQuery()
    }

    func testImmediateReplyAndInvalidTimeouts() throws {
        let connection = QueryConnection()
        let frame = try AlarmQueryTests.capturedFrame()
        connection.onWrite = { connection.onData?(frame) }
        XCTAssertEqual(try TimeboxQueryReader.read(.alarms, from: connection).count, 10)
        XCTAssertFalse(connection.waited)
        for timeout in [0.0, -1, .nan, .infinity, 60.1] {
            let invalid = QueryConnection()
            XCTAssertThrowsError(try TimeboxQueryReader.read(.alarms, from: invalid, timeout: timeout)) {
                XCTAssertEqual($0 as? TimeboxQueryError, .invalidArguments)
            }
            XCTAssertTrue(invalid.isConnected)
            XCTAssertNil(invalid.request)
        }
    }
}
