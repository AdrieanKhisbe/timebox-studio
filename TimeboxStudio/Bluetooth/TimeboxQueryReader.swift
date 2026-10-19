import Foundation
import TimeboxKit

/// Raw receive capability, separate from write-only/BLE transports. Delivery and
/// all query operations must occur on the main thread. Ownership is exclusive:
/// beginQuery must reject another query or in-flight write; while acquired,
/// reject ordinary writes/reconnects and permit exactly one writeQuery call.
/// A query reader always disconnects; reconnect before a subsequent request.
public protocol TimeboxQueryTransport: AnyObject {
    var isConnected: Bool { get }
    var onData: ((Data) -> Void)? { get set }
    func beginQuery() throws
    func endQuery()
    func writeQuery(_ data: Data) throws
    func waitForQuery(milliseconds: Int)
    func disconnect()
}

public enum TimeboxQueryError: LocalizedError, Equatable {
    case timeout, disconnected, cancelled, busy, invalidArguments, unsupported
    case invalidResponse(String)
    public var errorDescription: String? {
        switch self {
        case .timeout: return "Timed out waiting for the device response."
        case .disconnected: return "Disconnected before receiving a complete device response."
        case .cancelled: return "Device query cancelled."
        case .busy: return "The connection is busy; use a fresh dedicated connection for a query."
        case .invalidArguments: return "Queries require the main thread and a finite timeout greater than zero and at most 60 seconds."
        case .unsupported: return "Live queries currently require macOS Classic Bluetooth."
        case .invalidResponse(let reason): return "Invalid device response: \(reason)"
        }
    }
}

public enum TimeboxQueryReader {
    /// Runs exactly one request on an exclusively owned, fresh connection.
    /// Closing on success as well as failure excludes duplicate/late responses
    /// from a later identical query; serialization alone would not do so.
    /// Unknown command replies are ignored, malformed frames fail closed.
    public static func read<Response>(_ query: TimeboxQuery<Response>, from transport: TimeboxQueryTransport,
                                      timeout: TimeInterval = 5,
                                      isCancelled: () -> Bool = { false }) throws -> Response {
        guard Thread.isMainThread, timeout.isFinite, timeout > 0, timeout <= 60 else {
            throw TimeboxQueryError.invalidArguments
        }
        guard transport.onData == nil else { throw TimeboxQueryError.busy }
        try transport.beginQuery()
        defer { transport.onData = nil; transport.disconnect(); transport.endQuery() }
        guard transport.isConnected else { throw TimeboxQueryError.disconnected }
        if isCancelled() { throw TimeboxQueryError.cancelled }
        var decoder = TimeboxResponseDecoder()
        var result: Result<Response, Error>?
        transport.onData = { data in
            guard result == nil else { return }
            do {
                for frame in try decoder.append(data) where frame.command == query.responseCommand && query.matchesResponseData(frame.data) {
                    result = .success(try query.decode(frame.data))
                    break
                }
            } catch { result = .failure(TimeboxQueryError.invalidResponse(error.localizedDescription)) }
        }
        try transport.writeQuery(query.request)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while result == nil {
            if isCancelled() { throw TimeboxQueryError.cancelled }
            guard transport.isConnected else { throw TimeboxQueryError.disconnected }
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                if decoder.hasPendingBytes { throw TimeboxQueryError.invalidResponse("truncated frame before timeout") }
                throw TimeboxQueryError.timeout
            }
            transport.waitForQuery(milliseconds: 10)
        }
        if isCancelled() { throw TimeboxQueryError.cancelled }
        guard let result else { throw TimeboxQueryError.invalidResponse("missing response") }
        return try result.get()
    }

    /// Opens a dedicated Classic link. Existing BLE/RCSP writes are unaffected;
    /// receive framing over RCSP has not been established by the Evo capture.
    @MainActor
    public static func read<Response>(_ query: TimeboxQuery<Response>, device: TimeboxDevice,
                                      channel: UInt8? = nil, timeout: TimeInterval = 5) async throws -> Response {
        #if canImport(IOBluetooth)
        guard timeout.isFinite, timeout > 0, timeout <= 60 else { throw TimeboxQueryError.invalidArguments }
        let transport = IOBluetoothTimeboxTransport()
        defer { transport.disconnect() }
        if Task.isCancelled { throw TimeboxQueryError.cancelled }
        try transport.connectPumpingRunLoop(to: device, channelID: channel)
        return try read(query, from: transport, timeout: timeout, isCancelled: { Task.isCancelled })
        #else
        throw TimeboxQueryError.unsupported
        #endif
    }
}
