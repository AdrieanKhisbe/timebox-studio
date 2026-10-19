import Foundation

/// One Gregorian local wall-clock snapshot. The wire format carries no timezone.
public struct TimeboxClockSnapshot: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let second: Int
    /// Sunday = 0, Saturday = 6.
    public let weekday: Int

    public init(date: Date, timeZone: TimeZone = .current) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let fields = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        guard fields.era == 1, let year = fields.year, (1...9999).contains(year),
              let month = fields.month, let day = fields.day, let hour = fields.hour,
              let minute = fields.minute, let second = fields.second, let weekday = fields.weekday else {
            throw TimeboxClockError.unrepresentableDate
        }
        self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute; self.second = second; self.weekday = weekday - 1
    }

    var payload: Data {
        Data([0x18, UInt8(year % 100), UInt8(year / 100), UInt8(month), UInt8(day),
              UInt8(hour), UInt8(minute), UInt8(second), UInt8(weekday)])
    }
}

public enum TimeboxClockError: LocalizedError {
    case unrepresentableDate
    public var errorDescription: String? { "Clock sync requires a Gregorian date in years 1...9999 CE." }
}
