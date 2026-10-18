import XCTest
import TimeboxKit

final class TimeboxResponseTests: XCTestCase {
    func testFragmentedAndCoalescedResponseFrames() throws {
        // Derived ACK fixture follows the independently documented response
        // shape. The full captured alarm reply is exercised by query tests.
        let ack = Data([1, 6, 0, 4, 0x45, 0x55, 1, 0xA5, 0, 2])
        var decoder = TimeboxResponseDecoder()
        XCTAssertTrue(try decoder.append(ack.prefix(2)).isEmpty)
        XCTAssertTrue(try decoder.append(ack.dropFirst(2).prefix(4)).isEmpty)
        let frames = try decoder.append(Data(ack.dropFirst(6)) + ack)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].command, 0x45)
        XCTAssertEqual(frames[0].data, Data([1]))
        XCTAssertFalse(decoder.hasPendingBytes)
    }

    func testInvalidFramingAndChecksumsAreRejected() throws {
        let valid = try AlarmQueryTests.capturedFrame()
        for (index, value) in [(0, UInt8(0)), (1, 0), (3, 3), (5, 0), (valid.count - 1, 0), (valid.count - 2, 0)] {
            var invalid = valid
            invalid[index] = value
            var decoder = TimeboxResponseDecoder()
            XCTAssertThrowsError(try decoder.append(invalid))
        }
    }
}
