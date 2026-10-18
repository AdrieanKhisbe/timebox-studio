import Foundation

struct CommandOptions {
    var name: String?
    var address: String?
    var channel: UInt8?
    var brightness = 100
    var holdMilliseconds = 500
    var mock = false
    var all = false
    var positionals: [String] = []

    init(_ arguments: [String]) throws {
        var index = 0
        var selectorCount = 0
        while index < arguments.count {
            let argument = arguments[index]
            func value() throws -> String {
                guard index + 1 < arguments.count else { throw CommandFailure("invalid_arguments", "Missing value for \(argument).") }
                index += 1
                return arguments[index]
            }
            switch argument {
            case "--device", "--name": name = try value(); selectorCount += 1
            case "--address": address = try value(); selectorCount += 1
            case "--channel":
                let text = try value()
                guard let number = UInt8(text), number > 0 else { throw CommandFailure("invalid_arguments", "Channel must be 1...255.") }
                channel = number
            case "--brightness": brightness = try Self.percent(value())
            case "--hold-ms":
                let text = try value()
                guard let number = Int(text), number >= 0 else { throw CommandFailure("invalid_arguments", "--hold-ms requires a non-negative integer.") }
                holdMilliseconds = number
            case "--mock": mock = true
            case "--all": all = true
            default:
                guard !argument.hasPrefix("--") else { throw CommandFailure("invalid_arguments", "Unknown option: \(argument).") }
                positionals.append(argument)
            }
            index += 1
        }
        guard selectorCount <= 1 else { throw CommandFailure("invalid_arguments", "Choose one selector: --device/--name or --address.") }
    }

    static func percent(_ text: String) throws -> Int {
        guard let value = Int(text), (0...100).contains(value) else {
            throw CommandFailure("invalid_arguments", "Brightness must be an integer from 0 through 100.")
        }
        return value
    }
}
