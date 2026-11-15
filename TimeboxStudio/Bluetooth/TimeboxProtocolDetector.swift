import Foundation
import TimeboxKit

public struct TimeboxProtocolDetection: Sendable {
    public let family: TimeboxProtocolFamily
    public let settings: Data
    public let elapsedMilliseconds: Double
    public let queryMilliseconds: Double
}

public enum TimeboxProtocolDetectionError: LocalizedError {
    case unknownLayout(Int), conflictingReplies
    public var errorDescription: String? {
        switch self {
        case .unknownLayout(let count):
            return "Unrecognized settings layout (\(count) bytes). Set protocol: legacy11 or protocol: evo16 in the device config, or use --protocol."
        case .conflictingReplies:
            return "Conflicting settings replies; protocol could not be identified. Select --protocol explicitly."
        }
    }
}

/// One read-only settings snapshot, independent of retail model/name/channel.
/// Each request owns a fresh connection. No control encoding is used to probe.
public enum TimeboxProtocolDetector {
    public static func detect(device: TimeboxDevice, channel: UInt8? = nil,
                              timeout: TimeInterval = 5,
                              isCancelled: () -> Bool = { false },
                              makeTransport: () -> TimeboxDisplayTransport) throws -> TimeboxProtocolDetection {
        guard Thread.isMainThread, timeout.isFinite, timeout > 0, timeout <= 60 else { throw TimeboxQueryError.invalidArguments }
        let start = ProcessInfo.processInfo.systemUptime
        var querySeconds = 0.0
        let requests = [try TimeboxPacketEncoder.encodePayload(Data([0x46])), try TimeboxLegacyEncoder.frame(Data([0x46]))]
        for (index, packet) in requests.enumerated() {
            if isCancelled() { throw TimeboxQueryError.cancelled }
            if querySeconds >= timeout { throw TimeboxQueryError.timeout }
            let transport = makeTransport()
            defer { transport.disconnect() }
            try transport.connectForDisplay(to: device, channel: channel)
            transport.settleDisplay(milliseconds: 150)
            let queryStart = ProcessInfo.processInfo.systemUptime
            // A legacy device may ignore the canonical unescaped request. Only
            // that read timeout permits one escaped settings read on a new link.
            let budget = index == 0 ? min(0.35, timeout / 2) : max(0.001, timeout - querySeconds)
            do {
                let reply = try read(packet, from: transport, timeout: budget, isCancelled: isCancelled)
                querySeconds += ProcessInfo.processInfo.systemUptime - queryStart
                let family = try classify(reply)
                return TimeboxProtocolDetection(family: family, settings: reply.data,
                    elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1000,
                    queryMilliseconds: querySeconds * 1000)
            } catch TimeboxQueryError.timeout where index == 0 {
                querySeconds += ProcessInfo.processInfo.systemUptime - queryStart
            }
        }
        throw TimeboxQueryError.timeout
    }

    private static func classify(_ reply: SettingsReply) throws -> TimeboxProtocolFamily {
        let data = reply.data
        switch data.count {
        case 20 where reply.rawFraming:
            do { _ = try TimeboxStatusDecoder.decode(data, model: .evo) }
            catch { throw TimeboxQueryError.invalidResponse(error.localizedDescription) }
            return .evo16
        case 23 where reply.escapedFraming:
            do { _ = try TimeboxStatusDecoder.decode(data, model: .mini) }
            catch { throw TimeboxQueryError.invalidResponse(error.localizedDescription) }
            return .legacy11
        default: throw TimeboxProtocolDetectionError.unknownLayout(data.count)
        }
    }

    private static func read(_ packet: Data, from transport: TimeboxQueryTransport,
                             timeout: TimeInterval, isCancelled: () -> Bool) throws -> SettingsReply {
        guard transport.onData == nil else { throw TimeboxQueryError.busy }
        try transport.beginQuery()
        defer { transport.onData = nil; transport.disconnect(); transport.endQuery() }
        var decoder = SettingsReplyDecoder()
        var result: Result<SettingsReply, Error>?
        transport.onData = { data in
            guard result == nil else { return }
            do { if let value = try decoder.append(data) { result = .success(value) } }
            catch { result = .failure(error) }
        }
        if isCancelled() { throw TimeboxQueryError.cancelled }
        try transport.writeQuery(packet)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while result == nil {
            if isCancelled() { throw TimeboxQueryError.cancelled }
            guard transport.isConnected else { throw TimeboxQueryError.disconnected }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                if decoder.hasPartialSettings { throw TimeboxQueryError.invalidResponse("truncated settings frame during protocol detection") }
                throw TimeboxQueryError.timeout
            }
            transport.waitForQuery(milliseconds: 10)
        }
        if isCancelled() { throw TimeboxQueryError.cancelled }
        return try result!.get()
    }
}

/// A settings reply has the common 04/46/55 header. Try complete, independently
/// checksummed raw/escaped envelopes without assuming either dialect up front.
/// Greetings and unrelated notifications are not device/model identity.
private struct SettingsReply {
    let data: Data
    var rawFraming = false
    var escapedFraming = false
}

private struct SettingsReplyDecoder {
    var buffer = Data()
    var hasPartialSettings = false
    mutating func append(_ data: Data) throws -> SettingsReply? {
        buffer.append(data)
        guard buffer.count <= 4096 else { throw TimeboxQueryError.invalidResponse("protocol probe response exceeds bound") }
        let bytes = Array(buffer)
        var values: [Data: SettingsReply] = [:]
        hasPartialSettings = false
        for start in bytes.indices where bytes[start] == 1 {
            guard bytes.count - start >= 6 else { hasPartialSettings = true; continue }
            guard Array(bytes[(start + 3)...(start + 5)]) == [4,0x46,0x55] else { continue }
            hasPartialSettings = true
            let length = Int(bytes[start + 1]) | Int(bytes[start + 2]) << 8
            guard length >= 5, length <= 2048 else { throw TimeboxQueryError.invalidResponse("invalid settings length") }
            let rawEnd = start + length + 4
            var found = false
            if rawEnd <= bytes.count {
                var raw = TimeboxResponseDecoder(model: .evo)
                if let frames = try? raw.append(Data(bytes[start..<rawEnd])), frames.count == 1,
                   !raw.hasPendingBytes, frames[0].command == 0x46 {
                    let value = frames[0].data
                    var reply = values[value] ?? SettingsReply(data: value)
                    reply.rawFraming = true; values[value] = reply; found = true
                }
            }
            if let end = bytes[(start + 6)...].firstIndex(of: 2), end - start + 1 >= length + 4 {
                var escaped = TimeboxResponseDecoder(model: .mini)
                if let frames = try? escaped.append(Data(bytes[start...end])), frames.count == 1,
                   !escaped.hasPendingBytes, frames[0].command == 0x46 {
                    let value = frames[0].data
                    var reply = values[value] ?? SettingsReply(data: value)
                    reply.escapedFraming = true; values[value] = reply; found = true
                }
                if !found { throw TimeboxQueryError.invalidResponse("invalid settings envelope/checksum") }
            }
        }
        guard values.count <= 1 else { throw TimeboxProtocolDetectionError.conflictingReplies }
        return values.values.first
    }
}
