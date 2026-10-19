import XCTest
import TimeboxKit

/// Exercise ordinary CLI/REPL boundaries after the independently developed tracks merge.
final class EvoCommandModelSafetyTests: XCTestCase {
    private let address = "AA:BB:CC:DD:EE:01"
    private let commands: [[String]] = [
        ["time", "sync"],
        ["countdown", "start", "00:05"], ["countdown", "stop"],
        ["text", "Hello"],
        ["status"],
        ["display", "clock", "--style", "0"],
        ["display", "light"], ["display", "design"], ["design", "1"],
        ["effect", "0"], ["display", "effects"]
    ]

    func testEvoOnlyCLICommandsRejectMiniBeforeAnyConnectionQueryOrWrite() {
        for command in commands {
            let harness = CommandHarness()
            // Even an apparently Evo detected identity must not override the explicit Mini selector.
            harness.detectedModels = [.evo]
            XCTAssertEqual(harness.run(command + ["--address", address, "--model", "mini", "--json"]), 1,
                           command.joined(separator: " ") + ": " + harness.stderr.joined())
            XCTAssertTrue(harness.rawStdout.contains("unsupported"), command.joined(separator: " "))
            XCTAssertTrue(harness.transport.connections.isEmpty, command.joined(separator: " "))
            XCTAssertTrue(harness.transport.packets.isEmpty, command.joined(separator: " "))
        }
    }

    func testEvoOnlyREPLCommandsRejectSavedMiniWithoutQueriesWritesOrReconnects() {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "mini", devices: ["mini": .init(mac: address, model: .mini)])
        harness.input = commands.map { $0.joined(separator: " ") } + ["target", "quit"]
        XCTAssertEqual(harness.run(["repl"]), 0)
        // Opening the REPL itself is allowed. No feature command may replace that connection or send.
        XCTAssertEqual(harness.transport.connections.count, 1)
        XCTAssertTrue(harness.transport.packets.isEmpty)
        XCTAssertEqual(harness.stderr.count, commands.count, harness.stderr.joined(separator: "\n"))
        XCTAssertTrue(harness.stderr.allSatisfy { $0.contains("Mini does not yet support") },
                      harness.stderr.joined(separator: "\n"))
    }
}
