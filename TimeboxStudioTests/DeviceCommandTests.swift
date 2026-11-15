import XCTest
@testable import TimeboxCommands

final class DeviceCommandTests: XCTestCase {
    func testCLIAndREPLShareIndependentGoldenPackets() throws {
        let examples: [(String, [String], String, [UInt8])] = [
            ("brightness", ["50"], "bright 50", [1, 4, 0, 0x74, 50, 0xAA, 0, 2]),
            ("color", ["FF0000", "30"], "color FF0000 30", [1, 13, 0, 0x45, 1, 255, 0, 0, 30, 0, 1, 0, 0, 0, 0x71, 1, 2])
        ]
        for (name, args, line, golden) in examples {
            XCTAssertEqual(Array(try DeviceCommand(name: name, arguments: args).encoded()), golden)
            XCTAssertEqual(Array(try DeviceCommand(replLine: line).encoded()), golden)
        }
    }

    func testInvalidInputNeverReachesTheWriter() {
        for line in ["brightness -1", "brightness 101", "brightness 5 junk", "color FF0000 nope", "color 000000 101"] {
            var written = false
            XCTAssertThrowsError(try DeviceCommand(replLine: line).execute { _ in written = true })
            XCTAssertFalse(written)
        }
    }

    func testRawPacketsRetainTheirEnvelope() throws {
        let packet: [UInt8] = [1, 4, 0, 0x74, 50, 0xAA, 0, 2]
        XCTAssertEqual(Array(try DeviceCommand(replLine: "hex 01 04 00 74 32 AA 00 02").encoded()), packet)
        XCTAssertEqual(Array(try DeviceCommand(replLine: "01 04 00 74 32 AA 00 02").encoded()), packet)
    }
}
