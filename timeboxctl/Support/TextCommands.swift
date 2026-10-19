import Foundation
import TimeboxKit

extension TimeboxCommandLine {
    func prepareTextStream(_ text: String, model: TimeboxModel) throws -> TimeboxTextStream {
        do {
            let stream = try TimeboxTextStream(text, model: model)
            environment.errorOutput("Text font: \(stream.fontName) (\(model == .mini ? 9 : 12)px). Streaming one complete scroll; keep this process connected.")
            return stream
        } catch { throw CommandFailure("invalid_media", error.localizedDescription) }
    }

    func streamText(_ stream: TimeboxTextStream, using transport: CommandTransport) throws {
        guard transport.isConnected else { throw CommandFailure("connection_failed", "The selected target is disconnected.") }
        var deadline = environment.monotonicTime()
        for (index, packet) in stream.packets.enumerated() {
            deadline = max(deadline, environment.monotonicTime()) + Double(stream.frameMilliseconds) / 1000
            do { try transport.write(packet) }
            catch { throw CommandFailure("write_failed", "Text stream stopped after \(index) of \(stream.packets.count) frames; not retried: " + error.localizedDescription) }
            let remaining = deadline - environment.monotonicTime()
            if remaining > 0 { transport.wait(milliseconds: Int(ceil(remaining * 1000))) }
        }
    }

    func sendTextStream(_ stream: TimeboxTextStream, to target: ResolvedDevice, options: CommandOptions) throws {
        let transport = environment.makeTransport(options.mock)
        defer { transport.disconnect() }
        try connect(transport, to: target, channel: options.channel)
        transport.wait(milliseconds: 150)
        try streamText(stream, using: transport)
        diagnostic(options.mock ? "Simulated complete text scroll." : "Completed one text scroll.")
    }

    func textStreamData(_ stream: TimeboxTextStream) -> [String: Any] {
        ["font": stream.fontName, "playback": "host_stream", "frames": stream.packets.count,
         "frame_interval_ms": stream.frameMilliseconds, "target_duration_ms": stream.durationMilliseconds,
         "bytes": stream.packets.reduce(0) { $0 + $1.count }, "completed": true, "repeats": false]
    }

    /// --stream is a leading REPL option; quoted occurrences inside a message
    /// remain text. Normal CLI options may appear before or after its message.
    static func replTextStream(_ line: String) throws -> (text: String, stream: Bool) {
        let remainder = line.drop(while: { $0.isWhitespace }).drop(while: { !$0.isWhitespace }).trimmingCharacters(in: .whitespaces)
        let flag = remainder == "--stream" || remainder.hasPrefix("--stream ") || remainder.hasPrefix("--stream\t")
        let message = flag ? String(remainder.dropFirst(8)).trimmingCharacters(in: .whitespaces) : remainder
        if flag, message.hasPrefix("--") {
            throw CommandFailure("invalid_arguments", "Use target NAME to select the REPL device; quote a text message beginning with --.")
        }
        return (try replText("text " + message), flag)
    }

    func prepareText(_ options: CommandOptions) throws -> (upload: TimeboxAnimationUpload, fontName: String) {
        guard options.positionals.count == 1 else { throw CommandFailure("invalid_arguments", "text requires one message; quote messages containing spaces.") }
        do {
            let rendered = try TimeboxTextRenderer.render(options.positionals[0])
            environment.errorOutput("Text font: " + rendered.fontName + " (12px).")
            return (try TimeboxAnimationEncoder.prepare(rendered.animation), rendered.fontName)
        } catch { throw CommandFailure("invalid_media", error.localizedDescription) }
    }

    /// Only an outer quote pair is syntax; inner literal quotes are retained.
    static func replText(_ line: String) throws -> String {
        let remainder = line.drop(while: { $0.isWhitespace }).drop(while: { !$0.isWhitespace }).trimmingCharacters(in: .whitespaces)
        guard let first = remainder.first, first == "\"" || first == "'" else { return remainder }
        guard remainder.count >= 2, remainder.last == first else { throw CommandFailure("invalid_arguments", "Close the quoted text message.") }
        let inner = String(remainder.dropFirst().dropLast())
        if first == "'" { return inner }
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
