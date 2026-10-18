import Foundation
import TimeboxREPL
import TimeboxCommands
import TimeboxBluetooth
import TimeboxKit
import TimeboxUtilities

/// One CLI invocation. All ordinary device commands share selection and Classic routing.
public final class TimeboxCommandLine {
    static var replVocabulary: [String] { REPLSuggestions.commands }
    var environment: CommandEnvironment
    public init(environment: CommandEnvironment) { self.environment = environment }

    public static func handles(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }
        if ["brightness", "color"].contains(command), arguments.contains("--uuid") { return false }
        return ["list", "brightness", "color", "image", "repl", "connect", "send-hex"].contains(command)
    }

    @discardableResult
    public func run(arguments: [String]) -> Int32 {
        do {
            guard let command = arguments.first else { throw CommandFailure("invalid_arguments", "A command is required.") }
            let options = try CommandOptions(Array(arguments.dropFirst()))
            guard command == "repl" || !options.hasREPLInputOptions else { throw CommandFailure("invalid_arguments", "Editor/history options are only valid when starting repl.") }
            if command == "list" { try list(options); return 0 }
            guard !options.all else { throw CommandFailure("invalid_arguments", "--all is only valid for list.") }
            let configuration = try environment.configuration()
            let target = try resolve(options, configuration: configuration)
            if command == "repl" { try repl(target, options: options); return 0 }
            if command == "connect" {
                guard options.positionals.isEmpty else { throw CommandFailure("invalid_arguments", "connect takes no positional arguments.") }
                let transport = environment.makeTransport(options.mock)
                defer { transport.disconnect() }
                try connect(transport, to: target, channel: options.channel)
                return 0
            }
            let packet = try packet(command, options: options)
            try send(packet, to: target, options: options)
            return 0
        } catch {
            let failure = Self.failure(error)
            environment.errorOutput(failure.message)
            return failure.exitCode
        }
    }

    func resolve(_ options: CommandOptions, configuration: DeviceConfiguration) throws -> ResolvedDevice {
        try DeviceResolver.resolve(name: options.name, address: options.address,
            environmentAddress: environment.variables["TIMEBOX_ADDRESS"], configuration: configuration) {
            try self.environment.discover(options.mock)
        }
    }

    func list(_ options: CommandOptions) throws {
        guard options.name == nil, options.address == nil, options.positionals.isEmpty,
              options.channel == nil else {
            throw CommandFailure("invalid_arguments", "list does not take a device/name/address selector or channel.")
        }
        let devices = try environment.discover(options.mock).filter { options.all || $0.isTimeboxCandidate }
        if devices.isEmpty { environment.output("No paired Timeboxes found."); return }
        for device in devices {
            environment.output("\(device.name)\n    address: \(device.address)\n    paired: \(device.isPaired ? "yes" : "no")\n    connected: \(device.isConnected ? "yes" : "no")")
        }
    }

    func connect(_ transport: CommandTransport, to target: ResolvedDevice, channel: UInt8?) throws {
        environment.output("Connecting to \(target.logicalName ?? target.device.name) (\(target.device.address))...")
        do { try transport.connect(to: target.device, channel: channel) }
        catch { throw CommandFailure("connection_failed", error.localizedDescription) }
        environment.output("Connected on RFCOMM channel \(transport.channel.map(String.init) ?? "unknown").")
    }

    func send(_ packet: Data, to target: ResolvedDevice, options: CommandOptions) throws {
        var lastError: Error?
        for attempt in 1...3 {
            let transport = environment.makeTransport(options.mock)
            do {
                try connect(transport, to: target, channel: options.channel)
                transport.wait(milliseconds: 150)
                do { try transport.write(packet) }
                catch { throw CommandFailure("write_failed", error.localizedDescription) }
                transport.wait(milliseconds: options.holdMilliseconds)
                transport.disconnect()
                environment.output(options.mock ? "Simulated \(packet.count) byte(s)." : "Sent \(packet.count) byte(s).")
                return
            } catch {
                transport.disconnect()
                lastError = error
                if attempt < 3 { transport.wait(milliseconds: 400) }
            }
        }
        throw lastError ?? CommandFailure("connection_failed", "Connection failed.")
    }

    func packet(_ command: String, options: CommandOptions) throws -> Data {
        do { return try DeviceCommand(name: command, arguments: options.positionals, brightness: options.brightness).encoded() }
        catch let error as DeviceCommandError { throw CommandFailure(error.kind, error.message) }
    }

    func repl(_ target: ResolvedDevice, options: CommandOptions) throws {
        guard options.positionals.isEmpty else { throw CommandFailure("invalid_arguments", "repl takes no positional arguments.") }
        let input = try environment.makeREPLInput?(options.editor, options.historyFile, []) ?? CallbackREPLInput(environment.readLine)
        defer { try? input.close() }
        let transport = environment.makeTransport(options.mock)
        defer { transport.disconnect() }
        try connect(transport, to: target, channel: options.channel)
        transport.wait(milliseconds: 150)
        environment.output("Persistent connection open. Commands: color, brightness, image, hex, help, quit.")
        while let line = try input.readLine(prompt: REPLPrompt.text(interactive: environment.isInteractive, noColor: environment.variables["NO_COLOR"] != nil)) {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = parts.first?.lowercased() else { continue }
            if ["quit", "exit", "q"].contains(command) { break }
            if ["help", "?"].contains(command) { environment.output("color RRGGBB [brightness], brightness 0..100, image PATH, hex BYTES, quit"); continue }
            do {
                var replOptions = try CommandOptions(Array(parts.dropFirst()))
                guard !replOptions.hasREPLInputOptions else { throw CommandFailure("invalid_arguments", "Editor/history options are only valid when starting repl.") }
                if command == "color", replOptions.positionals.count == 2 {
                    replOptions.brightness = try CommandOptions.percent(replOptions.positionals.removeLast())
                }
                if command == "image" { replOptions.positionals = [parts.dropFirst().joined(separator: " ")] }
                let data = try packet(command == "bright" ? "brightness" : command == "img" ? "image" : command,
                                      options: replOptions)
                guard transport.isConnected else { throw CommandFailure("connection_failed", "The selected target is disconnected.") }
                try transport.write(data)
                transport.wait(milliseconds: 60)
                environment.output(options.mock ? "simulated (\(data.count) bytes)" : "sent (\(data.count) bytes)")
            } catch { environment.errorOutput(Self.failure(error).message) }
        }
        try input.close()
        environment.output("Disconnected.")
    }

    static func failure(_ error: Error) -> CommandFailure {
        if let failure = error as? CommandFailure { return failure }
        return CommandFailure("execution_failed", error.localizedDescription)
    }
}
