import Foundation
import TimeboxBluetooth
import TimeboxKit
import TimeboxUtilities

/// One CLI invocation. All ordinary device commands share selection and Classic routing.
public final class TimeboxCommandLine {
    var environment: CommandEnvironment
    public init(environment: CommandEnvironment) { self.environment = environment }

    public static func handles(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }
        if ["brightness", "color"].contains(command), arguments.contains("--uuid") { return false }
        return ["list", "brightness", "color", "image", "repl", "connect", "send-hex", "device", "config"].contains(command)
    }

    @discardableResult
    public func run(arguments: [String]) -> Int32 {
        do {
            guard let command = arguments.first else { throw CommandFailure("invalid_arguments", "A command is required.") }
            let options = try CommandOptions(Array(arguments.dropFirst()))
            if command == "device" || command == "config" { try manage(command, options: options); return 0 }
            guard options.format == nil else { throw CommandFailure("invalid_arguments", "Output formats are currently supported by config show only.") }
            if command == "list" { try list(options); return 0 }
            guard !options.all, !options.save else { throw CommandFailure("invalid_arguments", "--all and --save are only valid for list.") }
            let configuration = try environment.configuration(options.configPath)
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
        let discovered = try environment.discover(options.mock)
        let configuration: DeviceConfiguration
        if options.save {
            configuration = try DeviceConfigFile(path: options.configPath).saveDiscovered(discovered).configuration
            let path = options.configPath.map { " --config " + Self.shellQuote($0) } ?? ""
            if let name = configuration.defaultName {
                environment.errorOutput("Default: \(name). Change it with: timeboxctl device select \(Self.shellQuote(name))\(path)")
                environment.errorOutput("Rename a logical device with: timeboxctl device rename \(Self.shellQuote(name)) 'new-name'\(path)")
            }
        } else { configuration = try environment.configuration(options.configPath) }
        let devices = discovered.filter { options.all || $0.isTimeboxCandidate }
        if devices.isEmpty { environment.output("No paired Timeboxes found."); return }
        for device in devices {
            let mac = try? DeviceResolver.canonicalMAC(device.address)
            let name = configuration.devices.keys.first { configuration.devices[$0]?.mac == mac }
            environment.output("\(name.map { $0 + " (" + device.name + ")" } ?? device.name)\n    address: \(device.address)\n    paired: \(device.isPaired ? "yes" : "no")\n    connected: \(device.isConnected ? "yes" : "no")")
        }
    }

    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

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
        switch command {
        case "brightness":
            guard options.positionals.count == 1 else { throw CommandFailure("invalid_arguments", "brightness requires one percentage.") }
            return try TimeboxPacketEncoder.encode(.setBrightness(CommandOptions.percent(options.positionals[0])))
        case "color":
            guard options.positionals.count == 1 else { throw CommandFailure("invalid_arguments", "color requires one RRGGBB value.") }
            let text = options.positionals[0].replacingOccurrences(of: "#", with: "")
            guard text.count == 6, let rgb = UInt32(text, radix: 16) else { throw CommandFailure("invalid_arguments", "Expected RRGGBB, for example FF0000.") }
            return try TimeboxPacketEncoder.encode(.lightningPlainColor(
                color: PixelRGB(red: UInt8((rgb >> 16) & 255), green: UInt8((rgb >> 8) & 255), blue: UInt8(rgb & 255)),
                brightnessPercent: options.brightness))
        case "image":
            guard options.positionals.count == 1 else { throw CommandFailure("invalid_arguments", "image requires one path; quote paths containing spaces.") }
            do {
                return try TimeboxPacketEncoder.encode(.image(ImageToPixelFrameConverter.loadPixelFrame(path: options.positionals[0])))
            } catch { throw CommandFailure("invalid_media", error.localizedDescription) }
        case "send-hex", "hex":
            guard !options.positionals.isEmpty else { throw CommandFailure("invalid_arguments", "Raw hex bytes are required.") }
            do { return try HexStringParser.data(from: options.positionals.joined(separator: " ")) }
            catch { throw CommandFailure("invalid_arguments", error.localizedDescription) }
        default: throw CommandFailure("invalid_arguments", "Unknown command: \(command).")
        }
    }

    func repl(_ initialTarget: ResolvedDevice, options: CommandOptions) throws {
        guard options.positionals.isEmpty else { throw CommandFailure("invalid_arguments", "repl takes no positional arguments.") }
        var target = initialTarget
        var transport = environment.makeTransport(options.mock)
        defer { transport.disconnect() }
        try connect(transport, to: target, channel: options.channel)
        transport.wait(milliseconds: 150)
        environment.output("Persistent connection open. Commands: target [NAME|current], color, brightness, image, hex, help, quit.")
        while true {
            if environment.isInteractive { environment.rawOutput("timebox> ") }
            guard let line = environment.readLine() else { break }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = parts.first?.lowercased() else { continue }
            if ["quit", "exit", "q"].contains(command) { break }
            if ["help", "?"].contains(command) { environment.output("target [NAME|current], color RRGGBB [brightness], brightness 0..100, image PATH, hex BYTES, quit"); continue }
            do {
                if command == "target" {
                    let name = parts.dropFirst().joined(separator: " ")
                    if name.isEmpty || name.lowercased() == "current" {
                        environment.output("Target: \(target.logicalName ?? "(unnamed)") | \(target.device.address) | \(transport.isConnected ? "connected" : "disconnected")")
                    } else {
                        // Resolve first: a typo must not tear down a working connection.
                        let configuration = try environment.configuration(options.configPath)
                        let selected = try DeviceResolver.resolve(name: name, address: nil,
                            environmentAddress: nil, configuration: configuration, discover: { [] })
                        transport.disconnect()
                        target = selected
                        transport = environment.makeTransport(options.mock)
                        do {
                            try connect(transport, to: target, channel: nil)
                            transport.wait(milliseconds: 150)
                        } catch {
                            transport.disconnect()
                            throw error
                        }
                    }
                    continue
                }
                var replOptions = try CommandOptions(Array(parts.dropFirst()))
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
        environment.output("Disconnected.")
    }

    static func failure(_ error: Error) -> CommandFailure {
        if let failure = error as? CommandFailure { return failure }
        return CommandFailure("execution_failed", error.localizedDescription)
    }
}
