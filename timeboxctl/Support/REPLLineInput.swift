import Foundation
#if os(macOS)
import REPLInputSupport
import Bestline
#endif

/// Exactly one owner renders the prompt. Configuration prompts are a separate boundary.
public protocol REPLLineInput: AnyObject {
    func readLine(prompt: String) throws -> String?
    func close() throws
}

public extension REPLLineInput { func close() throws {} }

enum REPLInputFactory {
    static func make(editor: String, historyFile: String?, deviceNames: [String],
                     stdinIsTerminal: Bool = isatty(STDIN_FILENO) != 0,
                     stdoutIsTerminal: Bool = isatty(STDOUT_FILENO) != 0) throws -> REPLLineInput {
        // No history loads/saves or ANSI terminal setup when redirected.
        guard editor == "bestline", stdinIsTerminal, stdoutIsTerminal,
              !["dumb", "cons25", "emacs"].contains(ProcessInfo.processInfo.environment["TERM"] ?? "") else {
            return PlainREPLInput(showPrompt: stdinIsTerminal && stdoutIsTerminal)
        }
        #if os(macOS)
        return try BestlineREPLInput(historyFile: historyFile, deviceNames: deviceNames)
        #else
        throw CommandFailure("unsupported", "The Bestline editor prototype is available on macOS only.")
        #endif
    }
}

private final class PlainREPLInput: REPLLineInput {
    let showPrompt: Bool
    init(showPrompt: Bool) { self.showPrompt = showPrompt }
    func readLine(prompt: String) -> String? {
        if showPrompt { FileHandle.standardOutput.write(Data(prompt.utf8)) }
        return Swift.readLine()
    }
}

/// The blocking editor owns the worker; Bluetooth callbacks and commands own main.
/// A bounded run-loop slice keeps callbacks responsive without concurrent dispatch.
final class RunLoopREPLInput: REPLLineInput {
    private let read: (String) throws -> String?
    init(read: @escaping (String) throws -> String?) { self.read = read }
    func readLine(prompt: String) throws -> String? {
        precondition(Thread.isMainThread, "Classic Bluetooth REPL must run on main")
        let completed = DispatchSemaphore(value: 0)
        let box = InputResult()
        DispatchQueue.global(qos: .userInitiated).async { [read] in
            box.value = Result { try read(prompt) }
            completed.signal()
        }
        while completed.wait(timeout: .now()) == .timedOut {
            if !RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02)) {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        return try box.value!.get()
    }
    private final class InputResult: @unchecked Sendable {
        // Semaphore signal/wait establishes publication; worker is the sole writer.
        var value: Result<String?, Error>?
    }
}

struct REPLSuggestions {
    let deviceNames: [String]
    static let commands = ["target", "status", "display", "design", "effect", "text", "animation", "alarm", "time", "countdown", "stopwatch", "color", "brightness", "image", "hex", "help", "quit", "exit"]
    func completions(_ input: String, position: Int) -> [String] {
        // Bestline's position is a byte offset. Completion strings replace the whole line.
        guard position == input.utf8.count else { return [] }
        let candidates = Self.commands + ["display clock", "display light", "display design", "time sync", "stopwatch start", "stopwatch stop", "stopwatch reset", "countdown start", "countdown stop", "alarm list", "alarm set", "alarm disable", "target current"] + deviceNames.map { "target " + $0 }
        return candidates.filter { $0.hasPrefix(input) && $0 != input }.sorted()
    }
    func hint(_ input: String) -> String? {
        let hints = ["brightness": " 0..100", "color": " RRGGBB [brightness]", "target": " [NAME|current]", "countdown": " start MM:SS | stop", "alarm": " list | set SLOT --time HH:MM | disable SLOT", "display": " clock | light | design"]
        return hints[input]
    }
}

#if os(macOS)
private final class BestlineREPLInput: REPLLineInput {
    // Bestline, its callbacks, terminal state, and its history are process globals.
    private static let editorLock = NSLock()
    private let historyFile: String?
    private let worker: RunLoopREPLInput
    private var closed = false

    init(historyFile: String?, deviceNames: [String]) throws {
        guard Self.editorLock.try() else { throw CommandFailure("invalid_arguments", "Another Bestline session is already active.") }
        self.historyFile = historyFile
        worker = RunLoopREPLInput { prompt in
            guard timebox_repl_install_input_hook() == 0 else { throw CommandFailure("input_failed", "Could not prepare terminal input handling.") }
            let line = Bestline.readLine(prompt: prompt)
            let interrupted = timebox_repl_remove_input_hook() != 0
            // The C read hook returns ECANCELED for Ctrl-C before Bestline's
            // default SIGINT dispatch. Upstream restores termios and returns nil.
            return interrupted ? nil : line
        }
        Bestline.freeHistory()
        if let historyFile, !Bestline.loadHistory(from: historyFile) {
            closed = true
            Self.editorLock.unlock()
            throw CommandFailure("input_failed", "Could not load REPL history from \(historyFile).")
        }
        let suggestions = REPLSuggestions(deviceNames: deviceNames)
        Bestline.setCompletionCallback { suggestions.completions($0, position: $1) }
        Bestline.setHintsCallback { suggestions.hint($0) }
        Bestline.setEmacsMode(false)
        Bestline.setMultilineMode(false)
    }

    func readLine(prompt: String) throws -> String? {
        guard !closed else { return nil }
        let line = try worker.readLine(prompt: prompt)
        if let line, !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Bestline.addToHistory(line) }
        return line
    }

    func close() throws {
        guard !closed else { return }
        closed = true
        defer {
            Bestline.setCompletionCallback { _, _ in [] }
            Bestline.setHintsCallback { _ in nil }
            Bestline.freeHistory()
            Bestline.disableRawMode()
            Self.editorLock.unlock()
        }
        if let historyFile, !Bestline.saveHistory(to: historyFile) {
            throw CommandFailure("input_failed", "Could not save REPL history to \(historyFile).")
        }
    }
    deinit { try? close() }
}
#endif
