import XCTest
@testable import TimeboxCLIKit

final class REPLEditorTests: XCTestCase {
    func testEditorFlagsRejectInvalidAndNonREPLUsageBeforeAnyIO() {
        for arguments in [["brightness", "30", "--editor", "bestline"],
                          ["config", "--history-file", "/not/created"],
                          ["repl", "--editor", "unknown"],
                          ["repl", "--editor", "plain", "--history-file", "/not/created"]] {
            let harness = CommandHarness()
            XCTAssertEqual(harness.run(arguments), 2)
            XCTAssertTrue(harness.transport.connections.isEmpty)
        }
    }

    func testInjectedEditorOwnsPromptAndUsesExistingDispatch() {
        let transport = RecordingCommandTransport()
        let editor = ScriptedEditor(["target", "brightness 30", "quit"])
        var raw = "", output = ""
        var factoryArguments: (String, String?, [String])?
        let environment = CommandEnvironment(discover: { _ in XCTFail("No discovery expected"); return [] },
            configuration: { _ in .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01")]) },
            makeTransport: { _ in transport }, detectModels: { _ in [.evo] },
            output: { output += $0 }, errorOutput: { XCTFail($0) }, rawOutput: { raw += $0 },
            readLine: { XCTFail("Configuration reader must not own REPL input"); return nil },
            makeREPLInput: { name, history, names in factoryArguments = (name, history, names); return editor },
            isInteractive: true, stdoutIsTerminal: true)
        XCTAssertEqual(TimeboxCommandLine(environment: environment).run(arguments: ["repl", "--editor", "bestline"]), 0)
        XCTAssertEqual(factoryArguments?.0, "bestline")
        XCTAssertNil(factoryArguments?.1)
        XCTAssertEqual(factoryArguments?.2, ["desk"])
        XCTAssertEqual(editor.prompts, Array(repeating: "timebox> ", count: 3))
        XCTAssertTrue(raw.isEmpty, "Prompt belongs to the editor only")
        XCTAssertTrue(output.contains("Target: desk"))
        XCTAssertEqual(transport.packets.count, 1)
        XCTAssertFalse(transport.isConnected)
        XCTAssertTrue(editor.closed)
    }

    func testRunLoopServicesMainThreadWhileWorkerWaitsForInput() throws {
        XCTAssertTrue(Thread.isMainThread)
        let callbackRan = DispatchSemaphore(value: 0)
        let input = RunLoopREPLInput { _ in
            XCTAssertFalse(Thread.isMainThread)
            guard callbackRan.wait(timeout: .now() + 2) == .success else {
                throw NSError(domain: "Main loop was starved", code: 1)
            }
            return "quit"
        }
        let timer = Timer(timeInterval: 0.03, repeats: false) { _ in
            XCTAssertTrue(Thread.isMainThread)
            callbackRan.signal()
        }
        RunLoop.main.add(timer, forMode: .default)
        defer { timer.invalidate() }
        XCTAssertEqual(try input.readLine(prompt: "test> "), "quit")
    }

    func testCompletionAndUsageHintsIncludeConfiguredLogicalNames() {
        let suggestions = REPLSuggestions(deviceNames: ["main-evo", "Office desk"])
        XCTAssertEqual(suggestions.completions("target Of", position: 9), ["target Office desk"])
        XCTAssertTrue(suggestions.completions("display ", position: 8).contains("display clock"))
        XCTAssertEqual(suggestions.completions("sto", position: 1), [])
        XCTAssertNotNil(suggestions.hint("alarm"))
        XCTAssertNil(suggestions.hint("hex AA"))
    }

    func testSessionOptionsInsideCommandsNeverSendPackets() {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01", model: .evo)])
        harness.input = ["brightness 50 --editor bestline", "alarm list --editor plain", "display clock --history-file /unused", "text --editor plain", "text --stream --history-file /unused", "quit"]
        XCTAssertEqual(harness.run(["repl"]), 0)
        XCTAssertTrue(harness.transport.packets.isEmpty)
        XCTAssertEqual(harness.stderr.filter { $0.contains("only when starting repl") }.count, 5)
    }

    func testQuotedTextRetainsLiteralEditorWordsAfterStreamWhitespace() {
        for whitespace in [" ", "\t"] {
            let harness = CommandHarness()
            harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01", model: .evo)])
            harness.input = ["text --stream" + whitespace + "\"--editor plain\"", "quit"]
            XCTAssertEqual(harness.run(["repl"]), 0)
            XCTAssertFalse(harness.transport.packets.isEmpty)
            XCTAssertFalse(harness.stderr.contains { $0.contains("only when starting repl") })
        }
    }

    func testNonTTYFactoryNeverLoadsHistoryOrEmitsANSI() throws {
        let input = try REPLInputFactory.make(editor: "bestline", historyFile: "/unreadable/missing/history",
                                             deviceNames: [], stdinIsTerminal: false, stdoutIsTerminal: true)
        try input.close() // Invalid file would fail if the enhanced editor were constructed.
    }

    private final class ScriptedEditor: REPLLineInput {
        var lines: [String], prompts: [String] = [], closed = false
        init(_ lines: [String]) { self.lines = lines }
        func readLine(prompt: String) -> String? { prompts.append(prompt); return lines.isEmpty ? nil : lines.removeFirst() }
        func close() { closed = true }
    }
}
