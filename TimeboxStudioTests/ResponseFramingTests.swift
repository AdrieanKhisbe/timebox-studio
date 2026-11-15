import XCTest
import TimeboxKit

final class ResponseFramingTests: XCTestCase {
    let frame = Data([1, 6, 0, 4, 0x99, 0x55, 7, 0xFF, 0, 2])

    func testFragmentationAndCoalescedReplies() throws {
        var decoder = TimeboxResponseDecoder()
        XCTAssertEqual(try decoder.append(Data(frame.prefix(3))), [])
        XCTAssertTrue(decoder.hasPendingBytes)
        let result = try decoder.append(Data(frame.dropFirst(3)) + frame)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].command, 0x99)
        XCTAssertEqual(result[0].data, Data([7]))
        XCTAssertFalse(decoder.hasPendingBytes)
    }

    func testCorruptFramesFailClosed() {
        for index in [0, 3, 7, 9] {
            var bad = frame
            bad[index] ^= 1
            var decoder = TimeboxResponseDecoder()
            XCTAssertThrowsError(try decoder.append(bad))
        }
    }
}
