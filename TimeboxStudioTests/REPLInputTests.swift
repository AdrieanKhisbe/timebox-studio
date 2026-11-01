import XCTest
@testable import TimeboxREPL

final class REPLInputTests: XCTestCase {
    func testMainRunLoopRemainsResponsiveDuringTerminalInput() throws {
        XCTAssertTrue(Thread.isMainThread)
        let callback = DispatchSemaphore(value: 0)
        let input = RunLoopREPLInput { _ in
            XCTAssertFalse(Thread.isMainThread)
            guard callback.wait(timeout: .now() + 2) == .success else {
                throw NSError(domain: "Main loop starved", code: 1)
            }
            return "quit"
        }
        let timer = Timer(timeInterval: 0.02, repeats: false) { _ in callback.signal() }
        RunLoop.main.add(timer, forMode: .default)
        defer { timer.invalidate() }
        XCTAssertEqual(try input.readLine(prompt: "test> "), "quit")
    }

    func testRedirectedInputNeverLoadsTerminalHistory() throws {
        let input = try REPLInputFactory.make(editor: "bestline", historyFile: "/missing/history", deviceNames: [],
                                             stdinIsTerminal: false, stdoutIsTerminal: true)
        try input.close()
    }

    func testVocabularyContainsOnlyAvailableCommands() {
        let initial = REPLSuggestions()
        XCTAssertEqual(initial.completions("bri", position: 3), ["brightness"])
        XCTAssertEqual(initial.completions("alarm", position: 5), [])
        XCTAssertNil(initial.hint("alarm"))
        let configured = REPLSuggestions(deviceNames: ["main-evo"], commands: ["target", "brightness"])
        XCTAssertEqual(configured.completions("target ma", position: 9), ["target main-evo"])
        XCTAssertEqual(configured.completions("bri", position: 1), [])
    }

    func testPromptHonorsTerminalAndColorPreferences() {
        XCTAssertEqual(REPLPrompt.text(interactive: true, noColor: false), "\u{001B}[1;34mtimebox\u{001B}[1;31m>\u{001B}[0m ")
        XCTAssertEqual(REPLPrompt.text(interactive: true, noColor: true), "timebox> ")
        XCTAssertEqual(REPLPrompt.text(interactive: false, noColor: false), "timebox> ")
    }
}
