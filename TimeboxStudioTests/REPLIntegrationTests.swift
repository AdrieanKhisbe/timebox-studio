import XCTest
import TimeboxKit
import TimeboxCLIKit
import TimeboxREPL

final class REPLIntegrationTests: XCTestCase {
    func testSelectedEditorOwnsThePromptAndUsesConfiguredTarget() {
        let transport = RecordingCommandTransport()
        let editor = ScriptedInput(["target", "brightness 30", "quit"])
        let config = DeviceConfiguration(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01", model: .evo)])
        var raw = ""
        var factoryArguments: (String, String?, [String])?
        let environment = CommandEnvironment(discover: { _ in XCTFail("Discovery not needed"); return [] },
            configuration: { _ in config }, makeTransport: { _ in transport },
            output: { _ in }, errorOutput: { XCTFail($0) }, rawOutput: { raw += $0 },
            readLine: { XCTFail("The REPL editor owns input"); return nil },
            isInteractive: true, stdoutIsTerminal: true, variables: ["NO_COLOR": "1"],
            makeREPLInput: { name, history, names in factoryArguments = (name, history, names); return editor })
        XCTAssertEqual(TimeboxCommandLine(environment: environment).run(arguments: ["repl"]), 0)
        XCTAssertEqual(factoryArguments?.0, "bestline")
        XCTAssertNil(factoryArguments?.1)
        XCTAssertEqual(factoryArguments?.2, ["desk"])
        XCTAssertEqual(editor.prompts, Array(repeating: "timebox> ", count: 3))
        XCTAssertTrue(raw.isEmpty)
        XCTAssertEqual(transport.packets.count, 1)
        XCTAssertFalse(transport.isConnected)
        XCTAssertTrue(editor.closed)
    }

    func testSessionOptionsInsideDeviceCommandsNeverSendPackets() {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01", model: .evo)])
        harness.input = ["brightness 50 --editor bestline", "alarm list --editor plain",
                         "display clock --history-file /unused", "text --editor plain",
                         "text --stream --history-file /unused", "animation /unused --editor plain", "quit"]
        XCTAssertEqual(harness.run(["repl"]), 0)
        XCTAssertTrue(harness.transport.packets.isEmpty)
        XCTAssertEqual(harness.stderr.filter { $0.contains("only valid when starting repl") }.count, 6)
    }

    func testQuotedEditorWordsRemainTextWithStreamWhitespace() {
        for whitespace in [" ", "\t"] {
            let harness = CommandHarness()
            harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01", model: .evo)])
            harness.input = ["text --stream" + whitespace + "\"--editor plain\"", "quit"]
            XCTAssertEqual(harness.run(["repl"]), 0)
            XCTAssertFalse(harness.transport.packets.isEmpty)
            XCTAssertTrue(harness.stdout.contains("completed one text scroll"))
            XCTAssertFalse(harness.stderr.contains { $0.hasPrefix("Error:") }, harness.stderr.joined())
        }
    }

    func testInvalidOrMisplacedEditorOptionsFailBeforeConnecting() {
        for arguments in [["brightness", "30", "--editor", "bestline"],
                          ["repl", "--editor", "unknown"],
                          ["repl", "--editor", "plain", "--history-file", "/unused"]] {
            let harness = CommandHarness()
            XCTAssertEqual(harness.run(arguments), 2)
            XCTAssertTrue(harness.transport.connections.isEmpty)
        }
    }

    private final class ScriptedInput: REPLLineInput {
        var lines: [String]
        var prompts: [String] = []
        var closed = false
        init(_ lines: [String]) { self.lines = lines }
        func readLine(prompt: String) -> String? {
            prompts.append(prompt)
            return lines.isEmpty ? nil : lines.removeFirst()
        }
        func close() { closed = true }
    }
}
