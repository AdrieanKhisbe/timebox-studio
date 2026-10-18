import Foundation
import XCTest
import TimeboxKit
import TimeboxUtilities

final class TimeboxAlarmWriteTests: XCTestCase {
    private func current(_ overrides: [String: Any] = [:]) throws -> TimeboxAlarm {
        var fields: [String: Any] = [
            "slot": 2, "enabled": false, "hour": 0, "minute": 0,
            "weekdayMask": 0, "soundMode": 2, "triggerMode": 1,
            "frequencyBytes": [0, 0], "volume": 50
        ]
        fields.merge(overrides) { _, replacement in replacement }
        return try JSONDecoder().decode(TimeboxAlarm.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    func testEncodesObservedOnceAlarmPreservingSlotSoundSettings() throws {
        let schedule = try TimeboxAlarmSchedule(hour: 23, minute: 4)
        let packet = try TimeboxPacketEncoder.encode(.setAlarm(current(), schedule: schedule))
        // Actual slot 2 experiment, 2026-10-18: enabled at 23:04 with no day bits.
        XCTAssertEqual(packet, try HexStringParser.data(from: "01 0d 00 43 02 01 17 04 00 02 01 00 00 32 a3 00 02"))
    }

    func testDisablePreservesEveryOtherFieldAndOriginalRecordCanBeRestored() throws {
        let active = try current(["enabled": true, "hour": 23, "minute": 4])
        XCTAssertEqual(
            try TimeboxPacketEncoder.encode(.disableAlarm(active)),
            try HexStringParser.data(from: "01 0d 00 43 02 00 17 04 00 02 01 00 00 32 a2 00 02")
        )
        XCTAssertEqual(
            try TimeboxPacketEncoder.encode(.disableAlarm(current())),
            try HexStringParser.data(from: "01 0d 00 43 02 00 00 00 00 02 01 00 00 32 87 00 02")
        )
        let unknown = try current([
            "enabled": true, "weekdayMask": 255, "soundMode": 254,
            "triggerMode": 253, "frequencyBytes": [171, 205]
        ])
        let packet = try TimeboxPacketEncoder.encode(.disableAlarm(unknown))
        XCTAssertEqual(Array(packet[3..<14]), [0x43, 2, 0, 0, 0, 255, 254, 253, 171, 205, 50])
    }

    func testRejectsInvalidTimeRecurrenceWithoutDaysAndUnprovenFiniteWeekdays() throws {
        for hour in [-1, 24] {
            XCTAssertThrowsError(try TimeboxAlarmSchedule(hour: hour, minute: 0))
        }
        for minute in [-1, 60] {
            XCTAssertThrowsError(try TimeboxAlarmSchedule(hour: 0, minute: minute))
        }
        XCTAssertThrowsError(try TimeboxAlarmSchedule(hour: 7, minute: 30, recurring: true)) { error in
            XCTAssertEqual(error as? TimeboxAlarmWriteError, .recurrenceRequiresWeekdays)
        }
        XCTAssertThrowsError(try TimeboxAlarmSchedule(hour: 7, minute: 30, weekdays: [.mon, .tue])) { error in
            XCTAssertEqual(error as? TimeboxAlarmWriteError, .unsupportedFiniteWeekdays)
        }
        XCTAssertEqual(try TimeboxAlarmSchedule(hour: 0, minute: 0).weekdayMask, 0)
        XCTAssertEqual(try TimeboxAlarmSchedule(hour: 23, minute: 59).weekdayMask, 0)
    }

    func testRejectsMalformedCurrentRecordsDecodedFromExternalJSON() throws {
        let schedule = try TimeboxAlarmSchedule(hour: 7, minute: 30)
        let invalid: [[String: Any]] = [
            ["slot": -1], ["slot": 10], ["hour": -1], ["hour": 24],
            ["minute": -1], ["minute": 60], ["volume": -1],
            ["volume": 101], ["frequencyBytes": []], ["frequencyBytes": [0, 0, 0]]
        ]
        for fields in invalid {
            let record = try current(fields)
            XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.setAlarm(record, schedule: schedule)))
            XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.disableAlarm(record)))
        }
    }

    func testRecurringWeekdaysMatchTheIndependentUpstreamGolden() throws {
        let record = try current([
            "slot": 1, "soundMode": 1, "triggerMode": 1,
            "frequencyBytes": [11, 10], "volume": 80
        ])
        let schedule = try TimeboxAlarmSchedule(hour: 7, minute: 30, weekdays: [.mon, .wed, .fri], recurring: true)
        XCTAssertEqual(schedule.weekdayMask, 0x2a)
        // Pinned hass Timebox golden. Byte agreement is not a week-long firing test.
        XCTAssertEqual(
            try TimeboxPacketEncoder.encode(.setAlarm(record, schedule: schedule)),
            try HexStringParser.data(from: "01 0d 00 43 01 01 07 1e 2a 01 01 0b 0a 50 08 01 02")
        )
    }

    func testExplicitVolumeUsesDefinedBoundariesAndRejectsOutOfRangeValues() throws {
        let record = try current()
        let schedule = try TimeboxAlarmSchedule(hour: 23, minute: 4)
        XCTAssertEqual(
            try TimeboxPacketEncoder.encode(.setAlarm(record, schedule: schedule, volume: 0)),
            try HexStringParser.data(from: "01 0d 00 43 02 01 17 04 00 02 01 00 00 00 71 00 02")
        )
        XCTAssertEqual(
            try TimeboxPacketEncoder.encode(.setAlarm(record, schedule: schedule, volume: 100)),
            try HexStringParser.data(from: "01 0d 00 43 02 01 17 04 00 02 01 00 00 64 d5 00 02")
        )
        for volume in [-1, 101] {
            XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.setAlarm(record, schedule: schedule, volume: volume))) { error in
                XCTAssertEqual(error as? TimeboxAlarmWriteError, .invalidVolume(volume))
            }
        }
    }
}
