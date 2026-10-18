import Foundation
import Yams

extension TimeboxCommandLine {
    func manage(_ command: String, options: CommandOptions) throws {
        guard options.name == nil, options.address == nil, options.channel == nil, !options.all, !options.save, !options.mock else {
            throw CommandFailure("invalid_arguments", "Configuration commands do not take device, transport or discovery options.")
        }
        let file = DeviceConfigFile(path: options.configPath)
        let document = try file.read()
        if command == "config" {
            guard options.positionals == ["show"] else { throw CommandFailure("invalid_arguments", "Use config show [--yaml|--yml|--json].") }
            guard document.exists else { throw CommandFailure("invalid_config", "No configuration has been saved. Run timeboxctl list --save first.") }
            if options.format == .json {
                let value = try Yams.load(yaml: document.text) ?? [String: Any]()
                guard JSONSerialization.isValidJSONObject(value) else { throw CommandFailure("invalid_config", "Configuration contains values that cannot be represented as JSON.") }
                let bytes = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
                environment.rawOutput(String(decoding: bytes, as: UTF8.self) + "\n")
            } else { environment.rawOutput(document.text) }
            return
        }
        guard options.format == nil else { throw CommandFailure("invalid_arguments", "Output formats apply to config show, not device edits.") }
        guard let operation = options.positionals.first, ["select", "rename"].contains(operation) else {
            throw CommandFailure("invalid_arguments", "Use device select [NAME] or device rename [OLD [NEW]].")
        }
        let arguments = Array(options.positionals.dropFirst())
        guard arguments.count <= (operation == "select" ? 1 : 2) else { throw CommandFailure("invalid_arguments", "Too many arguments for device \(operation).") }
        let name: String
        if let explicit = arguments.first { name = explicit }
        else {
            guard environment.isInteractive else { throw CommandFailure("invalid_arguments", "A device name is required without terminal input.") }
            guard let selected = try chooseDevice(document.configuration) else { environment.errorOutput("Cancelled; config unchanged."); return }
            name = selected
        }
        guard document.configuration.name(matching: name) != nil else { throw CommandFailure("device_not_found", "Unknown logical device: \(name).") }
        if operation == "select" {
            let saved = try file.select(name)
            environment.output("Default device: \(saved.configuration.defaultName!).")
        } else {
            let newName: String
            if arguments.count == 2 { newName = arguments[1] }
            else {
                guard environment.isInteractive else { throw CommandFailure("invalid_arguments", "The new logical name is required without terminal input.") }
                environment.errorOutput("New logical name for '\(name)' (EOF to cancel):")
                guard let input = environment.readLine() else { environment.errorOutput("Cancelled; config unchanged."); return }
                newName = input
            }
            try file.rename(name, to: newName)
            environment.output("Renamed '\(name)' to '\(newName)'.")
        }
    }

    private func chooseDevice(_ configuration: DeviceConfiguration) throws -> String? {
        let names = configuration.devices.keys.sorted()
        guard !names.isEmpty else { throw CommandFailure("device_not_found", "No configured devices. Run timeboxctl list --save first.") }
        for (index, name) in names.enumerated() {
            environment.errorOutput("\(index + 1). \(name)\(name == configuration.defaultName ? " [default]" : "")")
        }
        environment.errorOutput("Choose a device by number or name (Enter: current default, q/EOF: cancel):")
        guard let input = environment.readLine(), input != "q" else { return nil }
        if input.isEmpty, let current = configuration.defaultName { return current }
        if let index = Int(input), names.indices.contains(index - 1) { return names[index - 1] }
        guard let name = configuration.name(matching: input) else { throw CommandFailure("device_not_found", "Unknown device selection: \(input).") }
        return name
    }
}
