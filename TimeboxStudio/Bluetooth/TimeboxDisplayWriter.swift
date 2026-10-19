import Foundation
import TimeboxKit

/// Main-run-loop driven Classic display/query boundary, injectable without radios.
/// BLE/Mini receive/capability semantics are not established by this Evo interface.
public protocol TimeboxDisplayTransport: TimeboxQueryTransport {
    func connectForDisplay(to device: TimeboxDevice, channel: UInt8?) throws
    func writeDisplay(_ data: Data) throws
    func settleDisplay(milliseconds: Int)
}

public struct TimeboxDisplayWriteResult: Equatable, Sendable {
    public let packetCount: Int
    public let byteCount: Int
}

public enum TimeboxDisplayWriter {
    /// Fresh query, strict profile/capability preparation, then a separate write
    /// connection. A capability failure sends no channel or tab-selection packet.
    /// `sent` describes transport completion; it is not a pixel-content readback.
    public static func perform(_ selection: TimeboxDisplay, device: TimeboxDevice,
                               channel: UInt8? = nil, timeout: TimeInterval = 5,
                               holdMilliseconds: Int = 500,
                               model: TimeboxModel = .evo,
                               isCancelled: () -> Bool = { false },
                               makeTransport: () -> TimeboxDisplayTransport) throws -> TimeboxDisplayWriteResult {
        guard model == .evo else { throw TimeboxModelError.unsupported("display channels and queries") }
        guard Thread.isMainThread, timeout.isFinite, timeout > 0, timeout <= 60,
              holdMilliseconds >= 0 else { throw TimeboxQueryError.invalidArguments }
        if isCancelled() { throw TimeboxQueryError.cancelled }
        try selection.validate()
        var commands: [TimeboxCommand]
        if let preserved = selection.preservedChannel {
            let snapshot = try read(.status, device: device, channel: channel,
                                    timeout: timeout, isCancelled: isCancelled, makeTransport: makeTransport)
            commands = [.displayProfile(try TimeboxDisplayProfile(channel: preserved, status: snapshot))]
        } else if case .design(let index?) = selection {
            let capability = try read(.designCapabilities, device: device, channel: channel,
                                      timeout: timeout, isCancelled: isCancelled, makeTransport: makeTransport)
            guard capability.supportsThreeTabs else { throw TimeboxDisplayError.designCapability(capability.rawFlag) }
            commands = [.display(.design()), .selectDesignTab(index)]
        } else { commands = [.display(selection)] }
        // Fully validate/encode every packet before the first control write.
        let packets = try commands.map { try TimeboxPacketEncoder.encode($0, model: model) }
        if isCancelled() { throw TimeboxQueryError.cancelled }
        let transport = makeTransport()
        defer { transport.disconnect() }
        try transport.connectForDisplay(to: device, channel: channel)
        transport.settleDisplay(milliseconds: 150)
        var sent = 0
        for packet in packets {
            if isCancelled() {
                if sent == 0 { throw TimeboxQueryError.cancelled }
                throw TimeboxDisplayError.incompleteWrite(sent: sent, total: packets.count, reason: TimeboxQueryError.cancelled.localizedDescription)
            }
            do { try transport.writeDisplay(packet) }
            catch { throw TimeboxDisplayError.incompleteWrite(sent: sent, total: packets.count, reason: error.localizedDescription) }
            sent += 1
            transport.settleDisplay(milliseconds: 60)
        }
        transport.settleDisplay(milliseconds: holdMilliseconds)
        transport.disconnect()
        if selection.requiresLivePreparation { transport.settleDisplay(milliseconds: 500) }
        return TimeboxDisplayWriteResult(packetCount: packets.count, byteCount: packets.reduce(0) { $0 + $1.count })
    }

    private static func read<Response>(_ query: TimeboxQuery<Response>, device: TimeboxDevice,
                                       channel: UInt8?, timeout: TimeInterval, isCancelled: () -> Bool,
                                       makeTransport: () -> TimeboxDisplayTransport) throws -> Response {
        let transport = makeTransport()
        defer { transport.disconnect() }
        // Existing REPL query transitions were validated with this run-loop gap.
        transport.settleDisplay(milliseconds: 500)
        try transport.connectForDisplay(to: device, channel: channel)
        transport.settleDisplay(milliseconds: 150)
        let response = try TimeboxQueryReader.read(query, from: transport, timeout: timeout, isCancelled: isCancelled)
        transport.settleDisplay(milliseconds: 500)
        return response
    }

    /// Production Classic adapter. Async dispatch services IOBluetooth callbacks
    /// on MainActor; callers must coordinate exclusive device access.
    @MainActor
    public static func send(_ selection: TimeboxDisplay, device: TimeboxDevice,
                            channel: UInt8? = nil, timeout: TimeInterval = 5,
                            holdMilliseconds: Int = 500,
                            model: TimeboxModel = .evo,
                            makeTransport: (() -> TimeboxDisplayTransport)? = nil) async throws -> TimeboxDisplayWriteResult {
        if let makeTransport {
            return try perform(selection, device: device, channel: channel, timeout: timeout,
                               holdMilliseconds: holdMilliseconds, model: model, isCancelled: { Task.isCancelled }, makeTransport: makeTransport)
        }
        #if canImport(IOBluetooth)
        return try perform(selection, device: device, channel: channel, timeout: timeout,
                           holdMilliseconds: holdMilliseconds, model: model, isCancelled: { Task.isCancelled }, makeTransport: { IOBluetoothTimeboxTransport() })
        #else
        throw TimeboxQueryError.unsupported
        #endif
    }
}

#if canImport(IOBluetooth)
extension IOBluetoothTimeboxTransport: TimeboxDisplayTransport {
    public func connectForDisplay(to device: TimeboxDevice, channel: UInt8?) throws {
        try connectPumpingRunLoop(to: device, channelID: channel)
    }
    public func writeDisplay(_ data: Data) throws { try writePumpingRunLoop(data) }
    public func settleDisplay(milliseconds: Int) { waitPumpingRunLoop(milliseconds: milliseconds) }
}

#endif
