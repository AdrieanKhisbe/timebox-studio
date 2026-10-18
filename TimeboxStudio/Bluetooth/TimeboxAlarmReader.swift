import Foundation
import TimeboxKit

/// A connected, exclusively owned Classic session. Its callbacks and pumping
/// operations run on the main thread. The reader closes it on every outcome.
public protocol TimeboxQueryTransport: AnyObject {
    var isConnected: Bool { get }
    var onData: ((Data) -> Void)? { get set }
    func writeQuery(_ data: Data) throws
    func waitForQuery(milliseconds: Int)
    func disconnect()
}

public enum TimeboxQueryError: LocalizedError, Equatable {
    case timeout, disconnected, cancelled, busy, invalidArguments, unsupported
    case invalidResponse(String)
    public var errorDescription: String? {
        switch self {
        case .timeout: return "Timed out waiting for the device's alarm response."
        case .disconnected: return "Disconnected before receiving a complete alarm response."
        case .cancelled: return "Alarm query cancelled."
        case .busy: return "The connection already has a receive handler; use a fresh dedicated connection."
        case .invalidArguments: return "Alarm reads require the main thread and a finite timeout from 0 through 60 seconds (exclusive of zero)."
        case .unsupported: return "Live alarm reads currently require macOS Classic Bluetooth."
        case .invalidResponse(let reason): return "Invalid alarm response: \(reason)"
        }
    }
}

public enum TimeboxAlarmReader {
    /// Complete enumeration is exactly ten records in one matching 0x42 reply.
    /// There is no request identifier. A fresh connection per read, closed even
    /// on success, prevents a late/duplicate reply from satisfying the next read.
    /// Other reply commands are ignored; no writes may interleave with this call.
    public static func read(from transport: TimeboxQueryTransport, timeout: TimeInterval = 5,
                            isCancelled: () -> Bool = { false }) throws -> [TimeboxAlarm] {
        guard Thread.isMainThread, timeout.isFinite, timeout > 0, timeout <= 60 else { throw TimeboxQueryError.invalidArguments }
        guard transport.onData == nil else { throw TimeboxQueryError.busy }
        defer { transport.onData = nil; transport.disconnect() }
        guard transport.isConnected else { throw TimeboxQueryError.disconnected }
        if isCancelled() { throw TimeboxQueryError.cancelled }
        var decoder = TimeboxResponseDecoder()
        var response: [TimeboxAlarm]?
        var failure: Error?
        transport.onData = { data in
            guard response == nil, failure == nil else { return }
            do {
                for frame in try decoder.append(data) where frame.command == 0x42 {
                    response = try TimeboxAlarmDecoder.decode(frame.data)
                    break
                }
            } catch { failure = TimeboxQueryError.invalidResponse(error.localizedDescription) }
        }
        // Literal independently checked against the manufacturer's empty-payload query.
        try transport.writeQuery(Data([1, 3, 0, 0x42, 0x45, 0, 2]))
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while response == nil, failure == nil {
            if isCancelled() { throw TimeboxQueryError.cancelled }
            guard transport.isConnected else { throw TimeboxQueryError.disconnected }
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                if decoder.hasPendingBytes { throw TimeboxQueryError.invalidResponse("truncated frame before timeout") }
                throw TimeboxQueryError.timeout
            }
            transport.waitForQuery(milliseconds: 10)
        }
        if let failure { throw failure }
        if isCancelled() { throw TimeboxQueryError.cancelled }
        guard let response else { throw TimeboxQueryError.invalidResponse("missing enumeration") }
        return response
    }

    /// Swift app entry point. A dedicated connection is opened and closed for
    /// this read; it must not compete with another controller's open RFCOMM link.
    @MainActor
    public static func read(device: TimeboxDevice, channel: UInt8? = nil,
                            timeout: TimeInterval = 5) async throws -> [TimeboxAlarm] {
        #if canImport(IOBluetooth)
        guard timeout.isFinite, timeout > 0, timeout <= 60 else { throw TimeboxQueryError.invalidArguments }
        let transport = IOBluetoothTimeboxTransport()
        defer { transport.disconnect() }
        if Task.isCancelled { throw TimeboxQueryError.cancelled }
        try transport.connectPumpingRunLoop(to: device, channelID: channel)
        return try read(from: transport, timeout: timeout, isCancelled: { Task.isCancelled })
        #else
        throw TimeboxQueryError.unsupported
        #endif
    }
}
