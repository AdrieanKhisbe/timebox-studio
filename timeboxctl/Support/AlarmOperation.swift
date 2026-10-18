import Foundation
import TimeboxKit

enum AlarmOperation {
    case list
    case set(Int, TimeboxAlarmSchedule, Int?)
    case disable(Int)

    var command: String {
        switch self { case .list: return "alarm list"; case .set: return "alarm set"; case .disable: return "alarm disable" }
    }

    init(_ options: CommandOptions) throws {
        if options.positionals == ["list"] {
            guard !options.hasAlarmWriteOptions else { throw CommandFailure("invalid_arguments", "alarm list does not take write options.") }
            self = .list
            return
        }
        guard options.positionals.count == 2, let operation = options.positionals.first,
              ["set", "disable"].contains(operation), let slot = Int(options.positionals[1]), (0...9).contains(slot) else {
            throw CommandFailure("invalid_arguments", "Use alarm list, alarm set SLOT --time HH:MM, or alarm disable SLOT (slots 0...9).")
        }
        if operation == "disable" {
            guard !options.hasAlarmWriteOptions else { throw CommandFailure("invalid_arguments", "alarm disable takes no schedule or volume options.") }
            self = .disable(slot)
            return
        }
        guard let time = options.alarmTime, time.count == 5, time[time.index(time.startIndex, offsetBy: 2)] == ":" else {
            throw CommandFailure("invalid_arguments", "alarm set requires --time HH:MM.")
        }
        let pieces = time.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2, pieces.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let hour = Int(pieces[0]), let minute = Int(pieces[1]) else {
            throw CommandFailure("invalid_arguments", "Expected a local device time in HH:MM form.")
        }
        var days = Set<TimeboxAlarmWeekday>()
        if let text = options.alarmDays {
            for value in text.split(separator: ",", omittingEmptySubsequences: false) {
                guard let day = TimeboxAlarmWeekday(rawValue: value.lowercased()), days.insert(day).inserted else {
                    throw CommandFailure("invalid_arguments", "Days must be unique comma-separated sun,mon,tue,wed,thu,fri,sat values.")
                }
            }
        }
        do { self = .set(slot, try TimeboxAlarmSchedule(hour: hour, minute: minute, weekdays: days), options.alarmVolume) }
        catch { throw TimeboxCommandLine.failure(error) }
    }
}
