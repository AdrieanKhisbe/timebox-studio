import XCTest
@testable import TimeboxBluetooth
import TimeboxKit

final class DeviceQueryTests: XCTestCase {
    // Synthetic opcode and independent envelope: not a claim about a device schema.
    static let frame = Data([1, 6, 0, 4, 0x99, 0x55, 7, 0xFF, 0, 2])
    static var query: TimeboxQuery<[UInt8]> {
        try! TimeboxQuery(payload: Data([0x99]), responseCommand: 0x99) { data in
            guard data.count == 1, data[0] == 7 else { throw TimeboxResponseError.malformed("schema") }
            return Array(data)
        }
    }

    func testGenericQueryRetainsTypedDecodingAndRejectsMalformedSchema() throws {
        // This envelope is synthetic; no settings opcode or schema is claimed.
        let query = try TimeboxQuery<Int>(payload: Data([0x99]), responseCommand: 0x99) { data in
            guard data.count == 1 else { throw TimeboxResponseError.malformed("schema") }
            return Int(data[0])
        }
        XCTAssertEqual(query.request, Data([1, 3, 0, 0x99, 0x9C, 0, 2]))
        let connection = QueryConnection()
        connection.chunks = [Self.frame]
        XCTAssertEqual(try TimeboxQueryReader.read(query, from: connection), 7)
        let malformed = QueryConnection()
        malformed.chunks = [try TimeboxPacketEncoder.encodePayload(Data([4, 0x99, 0x55, 1, 2]))]
        XCTAssertThrowsError(try TimeboxQueryReader.read(query, from: malformed)) {
            guard case .invalidResponse = $0 as? TimeboxQueryError else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(malformed.isConnected)
        XCTAssertFalse(malformed.access.queryInProgress)
    }

    func testQueryRejectsNestedQueriesAndWritesWhilePumping() throws {
        let connection = QueryConnection()
        connection.chunks = [Self.frame]
        var attempted = false
        connection.onWait = {
            attempted = true
            do { _ = try TimeboxQueryReader.read(Self.query, from: connection); XCTFail("Nested query accepted") }
            catch { XCTAssertEqual(error as? TimeboxQueryError, .busy) }
            do { try connection.writeQuery(Data([0x42])); XCTFail("Second request accepted") }
            catch { XCTAssertEqual(error as? TimeboxQueryError, .busy) }
            do { try connection.access.beginWrite(); XCTFail("Interleaved write accepted") }
            catch { XCTAssertEqual(error as? TimeboxQueryError, .busy) }
            XCTAssertTrue(connection.isConnected)
        }
        XCTAssertEqual(try TimeboxQueryReader.read(Self.query, from: connection).count, 1)
        XCTAssertTrue(attempted)
    }

    func testLateIdenticalReplyCannotCompleteQueryOnFreshLink() throws {
        let old = QueryConnection()
        var lateHandler: ((Data) -> Void)?
        old.onWait = { lateHandler = old.onData }
        XCTAssertThrowsError(try TimeboxQueryReader.read(Self.query, from: old, timeout: 0.001))
        XCTAssertFalse(old.isConnected)
        let fresh = QueryConnection()
        let frame = Self.frame
        fresh.onWait = { lateHandler?(frame) }
        // Injecting an old callback does not deliver to the new reader.
        XCTAssertThrowsError(try TimeboxQueryReader.read(Self.query, from: fresh, timeout: 0.001)) {
            XCTAssertEqual($0 as? TimeboxQueryError, .timeout)
        }
        XCTAssertFalse(fresh.isConnected)
    }

    func testCancellationBeforeSendingWriteFailureAndExistingHandlerCleanup() throws {
        let cancelled = QueryConnection()
        XCTAssertThrowsError(try TimeboxQueryReader.read(Self.query, from: cancelled, isCancelled: { true })) {
            XCTAssertEqual($0 as? TimeboxQueryError, .cancelled)
        }
        XCTAssertNil(cancelled.request)
        XCTAssertFalse(cancelled.isConnected)
        XCTAssertFalse(cancelled.access.queryInProgress)
        let failed = QueryConnection()
        failed.writeError = TimeboxTransportError.notConnected
        XCTAssertThrowsError(try TimeboxQueryReader.read(Self.query, from: failed)) {
            XCTAssertEqual($0 as? TimeboxTransportError, .notConnected)
        }
        XCTAssertNil(failed.onData)
        XCTAssertFalse(failed.isConnected)
        let busy = QueryConnection()
        var received = false
        busy.onData = { _ in received = true }
        XCTAssertThrowsError(try TimeboxQueryReader.read(Self.query, from: busy)) {
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
        let frame = Self.frame
        connection.onWrite = { connection.onData?(frame) }
        XCTAssertEqual(try TimeboxQueryReader.read(Self.query, from: connection).count, 1)
        XCTAssertFalse(connection.waited)
        for timeout in [0.0, -1, .nan, .infinity, 60.1] {
            let invalid = QueryConnection()
            XCTAssertThrowsError(try TimeboxQueryReader.read(Self.query, from: invalid, timeout: timeout)) {
                XCTAssertEqual($0 as? TimeboxQueryError, .invalidArguments)
            }
            XCTAssertTrue(invalid.isConnected)
            XCTAssertNil(invalid.request)
        }
    }
}
