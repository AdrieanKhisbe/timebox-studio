import Foundation
import TimeboxKit

enum OutputFormat: String { case json, yaml }

struct CommandOptions {
    var name: String?
    var model: TimeboxModel?
    var explicitAutoModel = false
    var address: String?
    var channel: UInt8?
    var brightness = 100
    var holdMilliseconds = 500
    var mock = false
    var all = false
    var save = false
    var configPath: String?
    var format: OutputFormat?
    var queryTimeout: TimeInterval?
    var alarmTime: String?
    var alarmDays: String?
    var alarmVolume: Int?
    var hasAlarmWriteOptions: Bool { alarmTime != nil || alarmDays != nil || alarmVolume != nil }
    var positionals: [String] = []

    init(_ arguments: [String]) throws {
        var index = 0
        var selectorCount = 0
        while index < arguments.count {
            let argument = arguments[index]
            func value() throws -> String {
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else { throw CommandFailure("invalid_arguments", "Missing value for \(argument).") }
                index += 1
                return arguments[index]
            }
            switch argument {
            case "--device", "--name": name = try value(); selectorCount += 1
            case "--address": address = try value(); selectorCount += 1
            case "--model":
                let text = try value()
                guard text == "auto" || TimeboxModel(rawValue: text) != nil else {
                    throw CommandFailure("invalid_arguments", "--model must be auto, evo or mini.")
                }
                model = TimeboxModel(rawValue: text); explicitAutoModel = text == "auto"
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
            case "--save": save = true
            case "--config": configPath = try value()
            case "--time": alarmTime = try value()
            case "--days": alarmDays = try value()
            case "--volume":
                let text = try value()
                guard let volume = Int(text), (0...100).contains(volume) else {
                    throw CommandFailure("invalid_arguments", "Alarm volume must be an integer from 0 through 100.")
                }
                alarmVolume = volume
            case "--timeout":
                let text = try value()
                guard let seconds = Double(text), seconds.isFinite, seconds > 0, seconds <= 60 else {
                    throw CommandFailure("invalid_arguments", "--timeout must be greater than zero and at most 60 seconds.")
                }
                queryTimeout = seconds
            case "--json", "--yaml", "--yml":
                let requested: OutputFormat = argument == "--json" ? .json : .yaml
                guard format == nil || format == requested else { throw CommandFailure("invalid_arguments", "Choose either JSON or YAML output.") }
                format = requested
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
