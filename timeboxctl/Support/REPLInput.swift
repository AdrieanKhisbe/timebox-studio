import Foundation
import CommandLineKit

public struct REPLInputConfiguration {
    public let historyFile: String?
    public let deviceNames: [String]
    public init(historyFile: String?, deviceNames: [String]) {
        self.historyFile = historyFile
        self.deviceNames = deviceNames
    }
}

/// One input owner, separate from configuration-management prompts.
public protocol REPLInput: AnyObject {
    func readLine(prompt: String) throws -> String?
    func finish() throws
}

/// The caller does not return until its sole terminal worker has finished.
/// Commands and Bluetooth operations remain on the calling main thread.
enum REPLInputPump {
    private final class ReadResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<String?, Error>?
        func store(_ value: Result<String?, Error>) {
            lock.lock(); defer { lock.unlock() }
            self.value = value
        }
        func take() -> Result<String?, Error>? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    static func read(_ operation: @escaping () throws -> String?) throws -> String? {
        precondition(Thread.isMainThread, "The REPL input pump must service the main run loop")
        let result = ReadResult()
        DispatchQueue(label: "timebox.repl.input").async {
            result.store(Result { try operation() })
        }
        while true {
            if let value = result.take() { return try value.get() }
            // IOBluetooth callbacks use the main run loop. No command can run
            // concurrently because the terminal worker owns only line input.
            if !RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
    }
}

/// CommandLineKit adapter. Upstream owns raw mode and restores it on all throws.
public final class CommandLineKitREPLInput: REPLInput {
    private let reader: LineReader
    private let historyFile: String?

    public init(configuration: REPLInputConfiguration) throws {
        guard LineReader.supportedByTerminal, let reader = LineReader() else {
            throw CommandFailure("unsupported", "CommandLineKit does not support this terminal; use --editor plain.")
        }
        self.reader = reader
        self.historyFile = configuration.historyFile
        reader.setHistoryMaxLength(1_024)
        reader.setCompletionCallback { REPLSuggestions.completions(for: $0, deviceNames: configuration.deviceNames) }
        reader.setHintsCallback { line in
            REPLSuggestions.hint(for: line).map { ($0, .dim) }
        }
        if let path = historyFile, FileManager.default.fileExists(atPath: path) {
            try reader.loadHistory(fromFile: path)
        }
    }

    public func readLine(prompt: String) throws -> String? {
        do {
            let line = try reader.readLine(prompt: prompt)
            // Upstream returns an empty string on actual descriptor EOF. Do
            // not repeatedly re-enter raw mode after a terminal disconnect.
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            if line.isEmpty, poll(&descriptor, 1, 0) > 0,
               descriptor.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { return nil }
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reader.addHistory(line) }
            return line
        } catch LineReaderError.CTRLC {
            FileHandle.standardOutput.write(Data("\n".utf8))
            return nil
        } catch LineReaderError.EOF { return nil }
    }

    public func finish() throws {
        if let path = historyFile { try reader.saveHistory(toFile: path) }
    }
}

/// Suggestions describe grammar; the existing dispatcher remains authoritative.
enum REPLSuggestions {
    static let commands = ["target", "status", "display", "design", "effect", "text", "animation", "alarm", "time", "countdown", "stopwatch", "color", "brightness", "image", "hex", "help", "quit", "exit"]
    static func completions(for line: String, deviceNames: [String]) -> [String] {
        let candidates = commands + ["display clock", "display light", "display design", "time sync",
            "stopwatch start", "stopwatch stop", "stopwatch reset", "countdown start", "countdown stop",
            "alarm list", "alarm set", "alarm disable", "target current"] + deviceNames.map { "target " + $0 }
        return candidates.filter { $0.hasPrefix(line) && $0 != line }.sorted()
    }

    static func hint(for line: String) -> String? {
        let usage = ["brightness": " 0..100", "color": " RRGGBB [brightness]", "target": " [NAME|current]",
            "countdown": " start MM:SS | stop", "alarm": " list | set SLOT --time HH:MM | disable SLOT",
            "display": " clock | light | design"]
        return usage[line]
    }
}
