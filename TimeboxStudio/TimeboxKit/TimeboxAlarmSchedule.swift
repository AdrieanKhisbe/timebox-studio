import Foundation

public enum TimeboxAlarmWeekday: String, CaseIterable, Sendable, Codable {
    case sun, mon, tue, wed, thu, fri, sat

    public var mask: UInt8 {
        switch self {
        case .sun: return 1
        case .mon: return 2
        case .tue: return 4
        case .wed: return 8
        case .thu: return 16
        case .fri: return 32
        case .sat: return 64
        }
    }
}

public enum TimeboxAlarmWriteError: LocalizedError, Equatable, Sendable {
    case invalidHour(Int)
    case invalidMinute(Int)
    case recurrenceRequiresWeekdays
    case unsupportedFiniteWeekdays
    case invalidSlot(Int)
    case invalidVolume(Int)
    case invalidFrequencyByteCount(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidHour(let value):
            return "Alarm hour \(value) is out of range. Use 0 through 23."
        case .invalidMinute(let value):
            return "Alarm minute \(value) is out of range. Use 0 through 59."
        case .recurrenceRequiresWeekdays:
            return "Recurring alarms require at least one weekday."
        case .unsupportedFiniteWeekdays:
            return "Finite weekday alarms remain unsupported pending firmware investigation. No alarm was sent."
        case .invalidSlot(let value):
            return "Alarm slot \(value) is out of range. Use 0 through 9."
        case .invalidVolume(let value):
            return "Alarm volume \(value) is out of range. Use 0 through 100."
        case .invalidFrequencyByteCount(let count):
            return "Alarm frequency must preserve exactly two device bytes; received \(count)."
        }
    }
}

/// Device-local wall-clock schedule; creating one never synchronizes the clock.
public struct TimeboxAlarmSchedule: Equatable, Sendable {
    public let hour: Int
    public let minute: Int
    public let weekdays: Set<TimeboxAlarmWeekday>
    public let recurring: Bool

    public init(hour: Int, minute: Int, weekdays: Set<TimeboxAlarmWeekday> = [], recurring: Bool = false) throws {
        guard (0...23).contains(hour) else { throw TimeboxAlarmWriteError.invalidHour(hour) }
        guard (0...59).contains(minute) else { throw TimeboxAlarmWriteError.invalidMinute(minute) }
        guard !recurring || !weekdays.isEmpty else { throw TimeboxAlarmWriteError.recurrenceRequiresWeekdays }
        guard recurring || weekdays.isEmpty else { throw TimeboxAlarmWriteError.unsupportedFiniteWeekdays }
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.recurring = recurring
    }

    public var weekdayMask: UInt8 {
        weekdays.reduce(0) { $0 | $1.mask }
    }
}
