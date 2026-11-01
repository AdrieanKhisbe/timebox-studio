import Foundation
import XCTest
import TimeboxKit
import TimeboxUtilities

final class TimeboxAlarmTests: XCTestCase {
    /// Actual main-evo reply data captured on 2026-10-18. The enclosing frame
    /// and provenance are in docs/validation/fixtures/evo-alarm-list-live.json.
    private func liveData() throws -> Data {
        try HexStringParser.data(from: """
        00 01 0a 00 08 03 00 00 00 32
        01 00 00 00 00 02 01 00 00 32
        02 00 00 00 00 02 01 00 00 32
        03 00 00 00 00 02 01 00 00 32
        04 00 00 00 00 02 01 00 00 32
        05 00 00 00 00 02 01 00 00 32
        06 00 00 00 00 02 01 00 00 32
        07 00 00 00 00 02 01 00 00 32
        08 00 00 00 00 02 01 00 00 32
        09 00 00 00 00 02 01 00 00 32
        """)
    }

    func testDecodesEveryCapturedSlotIncludingDisabledSlots() throws {
        let alarms = try TimeboxAlarmDecoder.decode(liveData())
        XCTAssertEqual(alarms.map(\.slot), Array(0...9))
        let first = try XCTUnwrap(alarms.first)
        XCTAssertTrue(first.enabled)
        XCTAssertEqual(first.hour, 10)
        XCTAssertEqual(first.minute, 0)
        XCTAssertEqual(first.weekdayMask, 8)
        XCTAssertEqual(first.weekdays, ["wed"])
        XCTAssertEqual(first.soundMode, 3)
        XCTAssertEqual(first.triggerMode, 0)
        XCTAssertEqual(first.frequencyBytes, [0, 0])
        XCTAssertEqual(first.volume, 50)
        XCTAssertNil(first.recurrence)
        XCTAssertTrue(alarms.dropFirst().allSatisfy { !$0.enabled })
        XCTAssertEqual(alarms[9].soundMode, 2)
        XCTAssertEqual(alarms[9].triggerMode, 1)
    }

    func testAllDisabledIsTenRecordsAndEmptyPayloadIsAnError() throws {
        var data = try liveData()
        data[1] = 0 // Derived test variant, not a second hardware capture.
        let alarms = try TimeboxAlarmDecoder.decode(data)
        XCTAssertEqual(alarms.count, 10)
        XCTAssertTrue(alarms.allSatisfy { !$0.enabled })
        XCTAssertThrowsError(try TimeboxAlarmDecoder.decode(Data())) { error in
            XCTAssertEqual(error as? TimeboxAlarmDecodingError, .invalidLength(0))
        }
    }

    func testRejectsPartialTrailingDuplicateAndOutOfRangeRecords() throws {
        let data = try liveData()
        for length in [10, 90, 99, 101] {
            var invalid = Data(data.prefix(length))
            if length > data.count { invalid.append(0) }
            XCTAssertThrowsError(try TimeboxAlarmDecoder.decode(invalid)) { error in
                XCTAssertEqual(error as? TimeboxAlarmDecodingError, .invalidLength(length))
            }
        }
        var duplicate = data
        duplicate[90] = 0
        XCTAssertThrowsError(try TimeboxAlarmDecoder.decode(duplicate)) { error in
            XCTAssertEqual(error as? TimeboxAlarmDecodingError, .duplicateSlot(0))
        }
        var outside = data
        outside[90] = 10
        XCTAssertThrowsError(try TimeboxAlarmDecoder.decode(outside)) { error in
            XCTAssertEqual(error as? TimeboxAlarmDecodingError, .invalidSlot(10))
        }
    }

    func testValidatesDefinedFieldsAndRetainsUnknownBytes() throws {
        let original = try liveData()
        let failures: [(Int, UInt8, TimeboxAlarmDecodingError)] = [
            (1, 2, .invalidEnabled(slot: 0, value: 2)),
            (2, 24, .invalidTime(slot: 0, hour: 24, minute: 0)),
            (3, 60, .invalidTime(slot: 0, hour: 10, minute: 60)),
            (9, 101, .invalidVolume(slot: 0, value: 101))
        ]
        for (offset, byte, expected) in failures {
            var invalid = original
            invalid[offset] = byte
            XCTAssertThrowsError(try TimeboxAlarmDecoder.decode(invalid)) { error in
                XCTAssertEqual(error as? TimeboxAlarmDecodingError, expected)
            }
        }
        var unknowns = original
        unknowns.replaceSubrange(2...9, with: [23, 59, 0xff, 0xfe, 0xfd, 0xab, 0xcd, 100])
        let first = try XCTUnwrap(TimeboxAlarmDecoder.decode(unknowns).first)
        XCTAssertEqual(first.hour, 23)
        XCTAssertEqual(first.minute, 59)
        XCTAssertEqual(first.weekdayMask, 0xff)
        XCTAssertEqual(first.weekdays, ["sun", "mon", "tue", "wed", "thu", "fri", "sat"])
        XCTAssertEqual(first.soundMode, 0xfe)
        XCTAssertEqual(first.triggerMode, 0xfd)
        XCTAssertEqual(first.frequencyBytes, [0xab, 0xcd])
        XCTAssertEqual(first.volume, 100)
        XCTAssertNil(first.recurrence)
    }

    func testSortsSlotIdentityIndependentlyOfRecordOrder() throws {
        let data = try liveData()
        var reordered = Data(data.suffix(10))
        reordered.append(data.prefix(90))
        XCTAssertEqual(try TimeboxAlarmDecoder.decode(reordered), try TimeboxAlarmDecoder.decode(data))
    }
}
