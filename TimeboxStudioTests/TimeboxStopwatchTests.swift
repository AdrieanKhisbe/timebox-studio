import XCTest
import TimeboxKit

final class TimeboxStopwatchTests: XCTestCase {
    func testReferenceFramesForAllActions() throws {
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.stopwatch(.start)), Data([1,5,0,0x72,0,1,0x78,0,2]))
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.stopwatch(.stop)), Data([1,5,0,0x72,0,0,0x77,0,2]))
        XCTAssertEqual(try TimeboxPacketEncoder.encode(.stopwatch(.reset)), Data([1,5,0,0x72,0,2,0x79,0,2]))
    }
    func testStatelessREPLSequencePreservesEveryRequestedTransition() throws {
        let h = CommandHarness()
        h.input = ["stopwatch reset", "stopwatch start", "stopwatch start", "stopwatch stop", "stopwatch stop", "stopwatch start", "stopwatch reset", "quit"]
        XCTAssertEqual(h.run(["repl", "--address", "AA:BB:CC:DD:EE:01"]), 0)
        XCTAssertEqual(h.transport.packets.map { $0[5] }, [2,1,1,0,0,1,2])
    }
    func testCLIResetStructuredOutputInvalidInputAndWriteFailure() {
        for action in ["start", "stop", "reset"] {
            let h = CommandHarness()
            XCTAssertEqual(h.run(["stopwatch", action, "--address", "AA:BB:CC:DD:EE:01", "--yaml"]), 0)
            XCTAssertTrue(h.rawStdout.contains("sent"))
            XCTAssertEqual(h.transport.packets.count, 1)
        }
        for args in [["stopwatch"], ["stopwatch", "pause"], ["stopwatch", "start", "extra"]] {
            let h = CommandHarness()
            XCTAssertEqual(h.run(args), 2); XCTAssertTrue(h.transport.connections.isEmpty)
        }
        let h = CommandHarness(); h.transport.failWrites = true
        XCTAssertEqual(h.run(["stopwatch", "start", "--address", "AA:BB:CC:DD:EE:01", "--json"]), 1)
        XCTAssertTrue(h.rawStdout.contains("write_failed")); XCTAssertFalse(h.rawStdout.contains("\"status\": \"sent\""))
    }
}
