import Foundation
import TimeboxKit
import TimeboxUtilities

public struct DeviceCommandError: LocalizedError {
    public let kind: String
    public let message: String
    public var errorDescription: String? { message }
    init(_ message: String, kind: String = "invalid_arguments") {
        self.message = message; self.kind = kind
    }
}

/// One validated device operation, independent of selectors and connection lifetime.
/// Both one-shot commands and REPL commands cross this boundary before device I/O.
public struct DeviceCommand {
    private let command: TimeboxCommand

    public init(name: String, arguments: [String], brightness: Int = 100) throws {
        func percent(_ text: String) throws -> Int {
            guard let value = Int(text), (0...100).contains(value) else {
                throw DeviceCommandError("Expected a percentage from 0 through 100.")
            }
            return value
        }
        switch name.lowercased() {
        case "brightness", "bright":
            guard arguments.count == 1 else { throw DeviceCommandError("brightness requires one percentage.") }
            command = .setBrightness(try percent(arguments[0]))
        case "color":
            guard (1...2).contains(arguments.count) else { throw DeviceCommandError("color requires RRGGBB [brightness].") }
            let text = arguments[0].hasPrefix("#") ? String(arguments[0].dropFirst()) : arguments[0]
            guard text.count == 6, let rgb = UInt32(text, radix: 16) else {
                throw DeviceCommandError("Expected RRGGBB, for example FF0000.")
            }
            let level = try percent(arguments.count == 2 ? arguments[1] : String(brightness))
            command = .lightningPlainColor(color: .init(red: UInt8((rgb >> 16) & 255), green: UInt8((rgb >> 8) & 255), blue: UInt8(rgb & 255)), brightnessPercent: level)
        case "image", "img":
            guard arguments.count == 1 else { throw DeviceCommandError("image requires one path; quote paths containing spaces.") }
            do { command = .image(try ImageToPixelFrameConverter.loadPixelFrame(path: arguments[0])) }
            catch { throw DeviceCommandError(error.localizedDescription, kind: "invalid_media") }
        case "hex", "send-hex":
            guard !arguments.isEmpty else { throw DeviceCommandError("Raw hex bytes are required.") }
            do { command = .raw(try HexStringParser.data(from: arguments.joined(separator: " "))) }
            catch { throw DeviceCommandError(error.localizedDescription) }
        default: throw DeviceCommandError("Unknown command: \(name).")
        }
    }

    public init(replLine: String) throws {
        let parts = replLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = parts.first else { throw DeviceCommandError("A command is required.") }
        let args = ["image", "img"].contains(name.lowercased())
            ? [parts.dropFirst().joined(separator: " ")] : Array(parts.dropFirst())
        // Keep the baseline raw-packet escape hatch without treating an unknown
        // ordinary command as a valid operation.
        if !["brightness", "bright", "color", "image", "img", "hex", "send-hex"].contains(name.lowercased()) {
            try self.init(name: "hex", arguments: parts)
        } else { try self.init(name: name, arguments: args) }
    }

    public func execute<Result>(write: (Data) throws -> Result) throws -> Result {
        try write(TimeboxPacketEncoder.encode(command))
    }

    public func encoded() throws -> Data { try execute { $0 } }
}
