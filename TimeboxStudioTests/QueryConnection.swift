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
