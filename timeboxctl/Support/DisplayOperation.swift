import Foundation
import TimeboxKit

struct DisplayOperation {
    let selection: TimeboxDisplay
    init(command: String, options: CommandOptions) throws {
        func fail() -> CommandFailure { CommandFailure("invalid_arguments", "Use display clock [--style ID], display light [--color RRGGBB] [--brightness 0..100], display design, display effects, design ID, or effect ID.") }
        let args = options.positionals
        if command == "design" {
            guard args.count == 1, let index = Int(args[0]), index >= 0,
                  options.displayStyle == nil, options.displayColor == nil, !options.hasBrightnessOption else { throw fail() }
            selection = .design(index: index); return
        }
        if command == "effect" {
            guard args.count == 1, let id = Int(args[0]), let effect = TimeboxEffect(rawValue: id),
                  options.displayStyle == nil, options.displayColor == nil, !options.hasBrightnessOption else {
                throw CommandFailure("invalid_arguments", "effect requires an Evo reference effect ID from 0 through 15.")
            }
            selection = .effects(effect: effect); return
        }
        guard command == "display", args.count == 1 else { throw fail() }
        switch args[0] {
        case "clock":
            guard options.displayColor == nil, !options.hasBrightnessOption else { throw fail() }
            if let id = options.displayStyle {
                guard let style = TimeboxClockStyle(rawValue: id) else { throw CommandFailure("invalid_arguments", "Clock style must be an Evo reference style ID from 0 through 5.") }
                selection = .clock(style: style)
            } else { selection = .clock() }
        case "light":
            guard options.displayStyle == nil else { throw fail() }
            let color: PixelRGB?
            if let text = options.displayColor {
                let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
                guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { throw CommandFailure("invalid_arguments", "--color requires RRGGBB.") }
                color = PixelRGB(red: UInt8((rgb >> 16) & 255), green: UInt8((rgb >> 8) & 255), blue: UInt8(rgb & 255))
            } else { color = nil }
            selection = .light(color: color, brightnessPercent: options.hasBrightnessOption ? options.brightness : nil)
        case "design", "effects":
            guard options.displayStyle == nil, options.displayColor == nil, !options.hasBrightnessOption else { throw fail() }
            selection = args[0] == "design" ? .design() : .effects()
        default: throw fail()
        }
    }
}
