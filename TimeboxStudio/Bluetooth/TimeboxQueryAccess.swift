import Foundation

/// Main-thread state shared by the Classic write and query entry points.
/// Not a correlation token: freshness comes from opening a new physical link.
struct TimeboxQueryAccess {
    private(set) var queryInProgress = false
    private(set) var writeInProgress = false
    private var usedConnection = false
    private var queryWritten = false
    var isBusy: Bool { queryInProgress || writeInProgress }

    mutating func didConnect() { usedConnection = false }

    mutating func beginQuery(isConnected: Bool, hasReceiveHandler: Bool) throws {
        guard !isBusy, !hasReceiveHandler else { throw TimeboxQueryError.busy }
        guard isConnected else { throw TimeboxQueryError.disconnected }
        guard !usedConnection else { throw TimeboxQueryError.busy }
        queryInProgress = true
        queryWritten = false
    }

    mutating func beginWrite(isQuery: Bool = false) throws {
        guard !writeInProgress else { throw TimeboxQueryError.busy }
        if isQuery {
            guard queryInProgress, !queryWritten else { throw TimeboxQueryError.busy }
            queryWritten = true
        } else {
            guard !queryInProgress else { throw TimeboxQueryError.busy }
        }
        usedConnection = true
        writeInProgress = true
    }

    mutating func endWrite() { writeInProgress = false }
    // Only the owner releases a query, even after an external disconnect.
    mutating func endQuery() { queryInProgress = false }
}
