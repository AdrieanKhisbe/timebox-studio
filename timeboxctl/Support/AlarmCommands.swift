import Foundation
import TimeboxKit
import TimeboxBluetooth

extension TimeboxCommandLine {
    func readAlarms(_ target: ResolvedDevice, options: CommandOptions) throws -> [TimeboxAlarm] {
        let transport = environment.makeTransport(false)
        defer { transport.disconnect() }
        try connect(transport, to: target, channel: options.channel)
        transport.wait(milliseconds: 150)
        // No retry of a timed-out query on the same link: replies have no request ID.
        do { return try TimeboxAlarmReader.read(from: transport, timeout: options.queryTimeout ?? 5) }
        catch let error as TimeboxQueryError { throw Self.failure(error) }
        catch { throw CommandFailure("write_failed", error.localizedDescription) }
    }

    static func alarmData(_ alarm: TimeboxAlarm) -> [String: Any] {
        ["slot": alarm.slot, "enabled": alarm.enabled,
         "time": String(format: "%02d:%02d", alarm.hour, alarm.minute),
         "hour": alarm.hour, "minute": alarm.minute,
         "weekdays": alarm.weekdays, "weekday_mask": Int(alarm.weekdayMask),
         "recurrence": NSNull(), "sound_mode_raw": Int(alarm.soundMode),
         "trigger_mode_raw": Int(alarm.triggerMode), "frequency_bytes": alarm.frequencyBytes.map { Int($0) },
         "volume": alarm.volume]
    }

    func showAlarms(_ alarms: [TimeboxAlarm]) {
        environment.output("Live device alarms (10 slots; recurrence and sound/trigger mode meanings unverified):")
        for alarm in alarms {
            let days = alarm.weekdays.isEmpty ? "no weekdays" : alarm.weekdays.joined(separator: ",")
            environment.output("\(alarm.slot): \(alarm.enabled ? "enabled" : "disabled") \(String(format: "%02d:%02d", alarm.hour, alarm.minute)) \(days) | volume \(alarm.volume) | sound mode \(alarm.soundMode), trigger mode \(alarm.triggerMode), weekday mask \(alarm.weekdayMask), frequency bytes \(alarm.frequencyBytes)")
        }
    }
}
