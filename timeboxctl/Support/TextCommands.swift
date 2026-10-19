import Foundation
import TimeboxKit

extension TimeboxCommandLine {
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
