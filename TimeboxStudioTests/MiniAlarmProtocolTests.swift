import XCTest
import Foundation
@testable import TimeboxKit
import TimeboxUtilities

final class MiniAlarmProtocolTests: XCTestCase {
    // AKTBR read42 capture, 2026-10-19; checksum and schema independently observed.
    private let captured = "01 23 00 04 42 55 00 00 00 00 00 00 03 04 00 00 32 03 04 00 00 00 00 00 03 04 00 00 32 03 05 00 00 00 00 00 03 04 00 00 32 5A 03 04 02"
    private let greeting = Data([0, 5, 0x48, 0x45, 0x4C, 0x4C, 0x4F, 0])
    private var records: Data {
        Data([0,0,0,0,0,0,1,0,0,50, 1,0,0,0,0,0,1,0,0,50, 2,0,0,0,0,0,1,0,0,50])
    }

    func testCapturedMiniAlarmAndGreetingAcrossEveryByteBoundary() throws {
        let frame = try HexStringParser.data(from: captured)
        let stream = greeting + frame + greeting + frame
        let expected = TimeboxResponseFrame(command: 0x42, data: records)
        for split in 0...stream.count {
            var decoder = TimeboxResponseDecoder(model: .mini)
            let first = try decoder.append(Data(stream.prefix(split)))
            let last = try decoder.append(Data(stream.dropFirst(split)))
            XCTAssertEqual(first + last, [expected, expected], "split \(split)")
            XCTAssertFalse(decoder.hasPendingBytes)
        }
        var decoder = TimeboxResponseDecoder(model: .mini)
        var output: [TimeboxResponseFrame] = []
        for byte in stream { output += try decoder.append(Data([byte])) }
        XCTAssertEqual(output, [expected, expected])
        let alarms = try TimeboxAlarmDecoder.decode(output[0].data, model: .mini)
        XCTAssertEqual(alarms.map(\.slot), [0,1,2])
        XCTAssertTrue(alarms.allSatisfy { !$0.enabled })
        XCTAssertEqual(try alarms.reduce(Data()) { $0 + (try $1.recordBytes) }, records)
    }

    func testMiniEscapesAllReservedBytesAndDoesNotTreatGreetingAsArbitraryNoise() throws {
        // Response data 01/02/03 are escaped, including an escaped length byte.
        let wire = try TimeboxMiniEncoder.frame(Data([4, 0x42, 0x55, 1, 2, 3]))
        for split in 0...wire.count {
            var decoder = TimeboxResponseDecoder(model: .mini)
            let result = try decoder.append(Data(wire.prefix(split))) + decoder.append(Data(wire.dropFirst(split)))
            XCTAssertEqual(result, [.init(command: 0x42, data: Data([1,2,3]))])
        }
        for prefix in [Data([0,6]), Data([0,5,0x48,0x45,0]), Data([0x7F])] {
            var decoder = TimeboxResponseDecoder(model: .mini)
            XCTAssertThrowsError(try decoder.append(prefix))
        }
        var partial = TimeboxResponseDecoder(model: .mini)
        XCTAssertEqual(try partial.append(Data(greeting.prefix(7))), [])
        XCTAssertTrue(partial.hasPendingBytes)
        XCTAssertEqual(try partial.append(Data(greeting.suffix(1))), [])
        XCTAssertFalse(partial.hasPendingBytes)
        // Greeting bytes inserted inside a frame cannot be skipped as a preamble.
        var inside = TimeboxResponseDecoder(model: .mini)
        XCTAssertThrowsError(try inside.append(Data([1,5,0,4]) + greeting + Data([2])))
    }

    func testMiniMalformedEscapesLengthsChecksumsAndWrongModelFailClosed() throws {
        for malformed in [Data([1,3,0]), Data([1,3,7]), Data([1,4,0]),
                          Data([1,5,0,4,0x42,0x55,1]), Data([1,5,0,4,2])] {
            var decoder = TimeboxResponseDecoder(model: .mini)
            XCTAssertThrowsError(try decoder.append(malformed))
        }
        var corrupted = try HexStringParser.data(from: captured)
        corrupted[corrupted.count - 4] = 0x5B
        var decoder = TimeboxResponseDecoder(model: .mini)
        XCTAssertThrowsError(try decoder.append(corrupted))
        var incomplete = TimeboxResponseDecoder(model: .mini)
        XCTAssertEqual(try incomplete.append(Data([1,3])), [])
        XCTAssertTrue(incomplete.hasPendingBytes)
        XCTAssertThrowsError(try incomplete.append(Data([2]))) // 03 02 is invalid escape
        var wrongEnvelope = TimeboxResponseDecoder(model: .mini)
        XCTAssertThrowsError(try wrongEnvelope.append(TimeboxMiniEncoder.frame(Data([4,0x42,0x54]) + records)))
        var evo = TimeboxResponseDecoder()
        XCTAssertThrowsError(try evo.append(HexStringParser.data(from: captured)))
        var mini = TimeboxResponseDecoder(model: .mini)
        XCTAssertThrowsError(try mini.append(TimeboxPacketEncoder.encodePayload(Data([4,0x42,0x55]) + records)))
    }

    func testMiniSlotCountAndSchemaAreStrictAndUnknownFieldsPreserved() throws {
        for invalid in [Data(), Data(records.dropLast()), records + Data([0]), Data(repeating: 0, count: 100)] {
            XCTAssertThrowsError(try TimeboxAlarmDecoder.decode(invalid, model: .mini))
        }
        XCTAssertThrowsError(try TimeboxAlarmDecoder.decode(records)) // Evo still requires ten
        for (index, value): (Int, UInt8) in [(10,0), (20,3), (1,2), (2,24), (3,60), (9,101)] {
            var bad = records; bad[index] = value
            XCTAssertThrowsError(try TimeboxAlarmDecoder.decode(bad, model: .mini))
        }
        var unknown = records
        unknown.replaceSubrange(24...28, with: [0x80,0xFE,0xFD,0xFC,0xFB])
        let alarms = try TimeboxAlarmDecoder.decode(unknown, model: .mini)
        XCTAssertEqual(try alarms[2].recordBytes, Data(unknown.suffix(10)))
        XCTAssertEqual(alarms[2].frequencyBytes, [0xFC,0xFB])
    }

    func testPublicCodableRecordRejectsInvalidValuesWithoutTrapping() throws {
        let valid = try XCTUnwrap(TimeboxAlarmDecoder.decode(records, model: .mini).first)
        let encoded = try JSONEncoder().encode(valid)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (key, value): (String, Any) in [("slot", -1), ("slot", 256), ("hour", 256),
                                          ("minute", -1), ("volume", 256), ("frequencyBytes", [0]) ] {
            var object = original
            object[key] = value
            // Existing public Codable behavior permits constructing invalid records;
            // byte serialization must validate before integer conversion/indexing.
            let alarm = try JSONDecoder().decode(TimeboxAlarm.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try alarm.recordBytes, key)
        }
        let decode: (Data) throws -> [TimeboxAlarm] = TimeboxAlarmDecoder.decode
        XCTAssertThrowsError(try decode(records)) // Original function reference remains Evo.
    }

    func testMiniQueryClockStopwatchAndAlarmIndependentWireFixtures() throws {
        let query = TimeboxQuery<[TimeboxAlarm]>.alarms(model: .mini)
        XCTAssertEqual(query.model, .mini)
        XCTAssertEqual(query.request, try HexStringParser.data(from: "01 03 06 00 42 45 00 02"))
        XCTAssertEqual(try query.decode(records).count, 3)
        XCTAssertEqual(TimeboxQuery<[TimeboxAlarm]>.alarms.model, .evo)
        let commands: [(TimeboxCommand, String)] = [
            (.display(.clock()), "01 05 00 45 00 03 04 4B 00 02"),
            (.stopwatch(.stop), "01 05 00 45 06 00 50 00 02"),
            (.stopwatch(.start), "01 05 00 45 06 03 04 51 00 02"),
            (.stopwatch(.reset), "01 05 00 45 06 03 05 52 00 02")
        ]
        for (command, hex) in commands {
            XCTAssertEqual(try TimeboxPacketEncoder.encode(command, model: .mini), try HexStringParser.data(from: hex))
        }
        let slot = try XCTUnwrap(query.decode(records).last)
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.disableAlarm(slot), model: .mini),
                       try HexStringParser.data(from: "01 0D 00 43 03 05 00 00 00 00 00 03 04 00 00 32 85 00 02"))
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.setAlarm(slot, schedule: .init(hour: 7, minute: 30)), model: .mini),
                       try HexStringParser.data(from: "01 0D 00 43 03 05 03 04 07 1E 00 00 03 04 00 00 32 AB 00 02"))
        // A valid Evo slot outside the Mini range must never be encoded for Mini.
        let wrongSlot = TimeboxAlarm(slot: 3, enabled: false, hour: 0, minute: 0, weekdayMask: 0,
            soundMode: 0, triggerMode: 1, frequencyBytes: [0,0], volume: 50)
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.disableAlarm(wrongSlot), model: .mini))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.setAlarm(wrongSlot, schedule: .init(hour: 7, minute: 30)), model: .mini))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.display(.clock(style: .rainbow)), model: .mini))
        XCTAssertThrowsError(try TimeboxPacketEncoder.encode(.stopCountdown, model: .mini))
    }
}
