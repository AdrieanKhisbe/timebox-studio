import Foundation

/// One of the ten configured slots returned by the Evo's `0x42` query.
/// Sound and trigger modes remain numeric until their Evo meanings are verified.
public struct TimeboxAlarm: Equatable, Sendable, Codable {
    public let slot: Int
    public let enabled: Bool
    public let hour: Int
    public let minute: Int
    public let weekdayMask: UInt8
    public let soundMode: UInt8
    public let triggerMode: UInt8
    public let frequencyBytes: [UInt8]
    public let volume: Int

    /// Known weekday bits in device order. The original mask preserves bit 7,
    /// whose meaning is unverified; it is not interpreted as a recurrence flag.
    public var weekdays: [String] {
        ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].enumerated().compactMap { bit, name in
            weekdayMask & (UInt8(1) << bit) != 0 ? name : nil
        }
    }

    /// The reply does not establish independent once/recurring semantics.
    public var recurrence: String? { nil }
}

public enum TimeboxAlarmDecodingError: LocalizedError, Equatable, Sendable {
    case invalidLength(Int)
    case invalidSlot(Int)
    case duplicateSlot(Int)
    case invalidEnabled(slot: Int, value: UInt8)
    case invalidTime(slot: Int, hour: Int, minute: Int)
    case invalidVolume(slot: Int, value: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLength(let length):
            return "Incomplete or malformed Evo alarm list: expected 100 data bytes for ten slots, received \(length)."
        case .invalidSlot(let slot):
            return "Malformed Evo alarm list: slot \(slot) is outside 0 through 9."
        case .duplicateSlot(let slot):
            return "Malformed Evo alarm list: slot \(slot) appears more than once."
        case let .invalidEnabled(slot, value):
            return "Malformed Evo alarm list: slot \(slot) has enabled byte \(value); expected 0 or 1."
        case let .invalidTime(slot, hour, minute):
            return "Malformed Evo alarm list: slot \(slot) has invalid time \(hour):\(minute)."
        case let .invalidVolume(slot, value):
            return "Malformed Evo alarm list: slot \(slot) has volume \(value); expected 0 through 100."
        }
    }
}

public enum TimeboxAlarmDecoder {
    /// Decodes the data after the successful `04 42 55` reply prefix.
    /// A complete Evo reply contains ten ten-byte records, including disabled
    /// slots. Framing, checksum and acknowledgement validation belong to the
    /// response layer. Missing bytes are never interpreted as an empty list.
    public static func decode(_ data: Data) throws -> [TimeboxAlarm] {
        guard data.count == 100 else {
            throw TimeboxAlarmDecodingError.invalidLength(data.count)
        }
        let bytes = Array(data)
        var seen = Set<Int>()
        var alarms: [TimeboxAlarm] = []
        for offset in stride(from: 0, to: bytes.count, by: 10) {
            let slot = Int(bytes[offset])
            guard (0...9).contains(slot) else {
                throw TimeboxAlarmDecodingError.invalidSlot(slot)
            }
            guard seen.insert(slot).inserted else {
                throw TimeboxAlarmDecodingError.duplicateSlot(slot)
            }
            let enabled = bytes[offset + 1]
            guard enabled <= 1 else {
                throw TimeboxAlarmDecodingError.invalidEnabled(slot: slot, value: enabled)
            }
            let hour = Int(bytes[offset + 2])
            let minute = Int(bytes[offset + 3])
            guard hour <= 23, minute <= 59 else {
                throw TimeboxAlarmDecodingError.invalidTime(slot: slot, hour: hour, minute: minute)
            }
            let volume = Int(bytes[offset + 9])
            guard volume <= 100 else {
                throw TimeboxAlarmDecodingError.invalidVolume(slot: slot, value: volume)
            }
            alarms.append(TimeboxAlarm(
                slot: slot, enabled: enabled == 1, hour: hour, minute: minute,
                weekdayMask: bytes[offset + 4], soundMode: bytes[offset + 5],
                triggerMode: bytes[offset + 6],
                frequencyBytes: [bytes[offset + 7], bytes[offset + 8]], volume: volume
            ))
        }
        return alarms.sorted { $0.slot < $1.slot }
    }
}
