import XCTest
@testable import TimeboxCLIKit

final class REPLEditorTests: XCTestCase {
    func testEditorArgumentsFailBeforeConfigDiscoveryOrTransport() {
        for args in [["brightness", "50", "--editor", "commandlinekit"],
                     ["list", "--history-file", "/unused"],
                     ["scan-ble", "--editor", "commandlinekit"],
                     ["repl", "--editor", "unknown"], ["repl", "--history-file", "/unused"]] {
            var touchedIO = false
            XCTAssertTrue(TimeboxCommandLine.handles(args))
            let environment = CommandEnvironment(discover: { _ in touchedIO = true; return [] },
                configuration: { _ in touchedIO = true; return .init() },
                makeTransport: { _ in touchedIO = true; return RecordingCommandTransport() },
                output: { _ in }, errorOutput: { _ in })
            XCTAssertEqual(TimeboxCommandLine(environment: environment).run(arguments: args), 2)
            XCTAssertFalse(touchedIO, args.joined(separator: " "))
        }
    }

    func testPlainAndRedirectedInputNeverConstructNativeEditorOrSaveHistory() {
        for (arguments, stdinTTY, stdoutTTY) in [
            (["repl"], true, true),
            (["repl", "--editor", "plain"], true, true),
            (["repl", "--editor", "commandlinekit", "--history-file", "/unused"], false, true),
            (["repl", "--editor", "commandlinekit"], true, false)] {
            let transport = RecordingCommandTransport()
            var input = ["brightness 50", "quit"]
            var nativeConstructed = false
            var environment = configuredEnvironment(transport: transport)
            environment.isInteractive = stdinTTY
            environment.stdoutIsTerminal = stdoutTTY
            environment.readLine = { input.isEmpty ? nil : input.removeFirst() }
            environment.makeREPLInput = { _ in nativeConstructed = true; return FakeInput() }
            XCTAssertEqual(TimeboxCommandLine(environment: environment).run(arguments: arguments), 0)
            XCTAssertFalse(nativeConstructed)
            XCTAssertEqual(transport.packets, [Data([1, 4, 0, 0x74, 50, 0xAA, 0, 2])])
            XCTAssertFalse(transport.isConnected)
        }
    }

    func testEnhancedInputOwnsPromptAndPreservesActualCommandDispatch() {
        let transport = RecordingCommandTransport()
        let input = FakeInput(lines: ["brightness 50", "quit"])
        var environment = configuredEnvironment(transport: transport)
        var rawOutput = ""
        environment.rawOutput = { rawOutput += $0 }
        environment.readLine = { XCTFail("Enhanced REPL used configuration prompt reader"); return nil }
        environment.makeREPLInput = { configuration in
            XCTAssertEqual(configuration.deviceNames, ["desk"])
            XCTAssertNil(configuration.historyFile)
            return input
        }
        XCTAssertEqual(TimeboxCommandLine(environment: environment).run(arguments: ["repl", "--editor", "commandlinekit"]), 0)
        XCTAssertEqual(input.prompts, ["timebox> ", "timebox> "])
        XCTAssertEqual(rawOutput, "")
        XCTAssertTrue(input.finished)
        XCTAssertFalse(input.readOnMain)
        XCTAssertEqual(transport.packets.count, 1)
        XCTAssertFalse(transport.isConnected)
    }

    func testMainRunLoopRemainsResponsiveWhileInputWorkerWaits() {
        XCTAssertTrue(Thread.isMainThread)
        let signal = DispatchSemaphore(value: 0)
        var callbackRan = false
        let timer = Timer(timeInterval: 0.03, repeats: false) { _ in
            XCTAssertTrue(Thread.isMainThread)
            callbackRan = true
            signal.signal()
        }
        RunLoop.main.add(timer, forMode: .default)
        defer { timer.invalidate() }
        let line = try? REPLInputPump.read {
            XCTAssertFalse(Thread.isMainThread)
            _ = signal.wait(timeout: .now() + 2)
            return "quit"
        }
        XCTAssertEqual(line, "quit")
        XCTAssertTrue(callbackRan, "Main-thread Bluetooth callbacks would stall while idle")
    }

    func testSessionOptionsInsideCommandsNeverSendPackets() {
        let harness = CommandHarness()
        harness.configuration = .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01", model: .evo)])
        harness.input = ["brightness 50 --editor commandlinekit", "alarm list --editor plain",
            "display clock --history-file /unused", "text --editor plain", "text --stream --history-file /unused", "quit"]
        XCTAssertEqual(harness.run(["repl"]), 0)
        XCTAssertTrue(harness.transport.packets.isEmpty)
        XCTAssertEqual(harness.stderr.filter { $0.contains("only when starting repl") }.count, 5)
    }

    func testSuggestionsIncludeGrammarAndConfiguredNamesWithoutClaimingValidation() {
        XCTAssertTrue(REPLSuggestions.completions(for: "target ", deviceNames: ["Office desk"]).contains("target Office desk"))
        XCTAssertEqual(REPLSuggestions.completions(for: "time ", deviceNames: []), ["time sync"])
        XCTAssertNotNil(REPLSuggestions.hint(for: "brightness"))
        XCTAssertNil(REPLSuggestions.hint(for: "brightness 101"))
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

    private func configuredEnvironment(transport: RecordingCommandTransport) -> CommandEnvironment {
        CommandEnvironment(discover: { _ in [] },
            configuration: { _ in .init(defaultName: "desk", devices: ["desk": .init(mac: "AA:BB:CC:DD:EE:01", model: .evo)]) },
            makeTransport: { _ in transport }, output: { _ in }, errorOutput: { _ in },
            isInteractive: true, stdoutIsTerminal: true)
    }
}

private final class FakeInput: REPLInput {
    var lines: [String]
    var prompts: [String] = []
    var finished = false
    var readOnMain = false
    init(lines: [String] = []) { self.lines = lines }
    func readLine(prompt: String) throws -> String? {
        readOnMain = readOnMain || Thread.isMainThread
        prompts.append(prompt)
        return lines.isEmpty ? nil : lines.removeFirst()
    }
    func finish() throws { finished = true }
}
