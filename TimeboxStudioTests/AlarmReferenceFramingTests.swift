import Foundation
import XCTest
import TimeboxKit
import TimeboxUtilities

final class AlarmReferenceFramingTests: XCTestCase {
    private struct Fixtures: Decodable {
        struct Reference: Decodable {
            let name: String
            let payload: String
            let packet: String
        }
        let cases: [Reference]
    }

    /// Tests existing generic framing against source-derived fixtures. This
    /// deliberately makes no claim that alarm scheduling is supported.
    func testReferenceAlarmPayloadsUseExistingEvoFraming() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/validation/fixtures/evo-alarm-reference.json")
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.cases.count, 6)
        for fixture in fixtures.cases {
            let payload = try HexStringParser.data(from: fixture.payload)
            let expected = try HexStringParser.data(from: fixture.packet)
            XCTAssertEqual(try TimeboxPacketEncoder.encodePayload(payload), expected, fixture.name)
        }
    }
}
