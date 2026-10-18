import Foundation
import TimeboxKit
import TimeboxBluetooth

extension TimeboxCommandLine {
    func performAlarm(_ operation: AlarmOperation, target: ResolvedDevice, options: CommandOptions) throws -> CommandResult {
        let before = try readAlarms(target, options: options)
        let slot: Int
        let command: TimeboxCommand
        switch operation {
        case .set(let index, let schedule, let volume):
            slot = index
            command = .setAlarm(before[index], schedule: schedule, volume: volume)
        case .disable(let index):
            slot = index
            command = .disableAlarm(before[index])
        case .list:
            if outputFormat == nil { showAlarms(before) }
            return CommandResult(command: operation.command, status: "ok", device: target, data: ["alarms": before.map(Self.alarmData)])
        }
        let packet = try TimeboxPacketEncoder.encode(command)
        // The snapshot reader closes its link. Give RFCOMM time to release it.
        let settle = environment.makeTransport(false)
        settle.wait(milliseconds: 500)
        try send(packet, to: target, options: options)
        settle.wait(milliseconds: 500)
        let after: [TimeboxAlarm]
        do { after = try readAlarms(target, options: options) }
        catch { throw CommandFailure("invalid_response", "Alarm packet sent, but live readback failed: \(error.localizedDescription)") }
        // Compare the actual response with the exact ten bytes requested, rather
        // than displaying requested values as though they came from the device.
        let actual = after[slot]
        let expectedRecord = Array(packet.dropFirst(4).prefix(10))
        let actualRecord: [UInt8] = [UInt8(actual.slot), actual.enabled ? 1 : 0, UInt8(actual.hour), UInt8(actual.minute),
            actual.weekdayMask, actual.soundMode, actual.triggerMode] + actual.frequencyBytes + [UInt8(actual.volume)]
        guard actualRecord == expectedRecord else { throw CommandFailure("invalid_response", "Alarm packet sent, but slot \(slot) readback differs; run alarm list to inspect device state.") }
        guard before.filter({ $0.slot != slot }) == after.filter({ $0.slot != slot }) else {
            throw CommandFailure("invalid_response", "Alarm packet sent, but other slots changed during the operation; inspect alarm list.")
        }
        if outputFormat == nil { environment.output("Slot \(slot): \(actual.enabled ? "enabled" : "disabled") at \(String(format: "%02d:%02d", actual.hour, actual.minute)); sent and device readback matches.") }
        return CommandResult(command: operation.command, status: "sent", device: target,
            data: ["slot": slot, "bytes": packet.count, "alarm": Self.alarmData(actual), "readback_matches": true])
    }

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
