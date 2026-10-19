import Foundation
import TimeboxBluetooth
import TimeboxKit
import TimeboxUtilities

/// One CLI invocation. All ordinary device commands share selection and Classic routing.
public final class TimeboxCommandLine {
    var environment: CommandEnvironment
    var outputFormat: OutputFormat?
    public init(environment: CommandEnvironment) { self.environment = environment }

    public static func handles(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }
        if arguments.contains(where: { ["--json", "--yaml", "--yml"].contains($0) }) { return true }
        if ["brightness", "color"].contains(command), arguments.contains("--uuid") { return false }
        return ["list", "brightness", "color", "image", "repl", "connect", "send-hex", "device", "config", "alarm", "time", "countdown", "stopwatch", "animation", "text", "status", "display", "design", "effect"].contains(command)
    }

    @discardableResult
    public func run(arguments: [String]) -> Int32 {
        // Keep even argument-validation failures machine-readable. With conflicting
        // flags the first requested format carries the error result.
        outputFormat = arguments.first(where: { ["--json", "--yaml", "--yml"].contains($0) })
            .map { $0 == "--json" ? .json : .yaml }
        let command = arguments.first ?? ""
        var resultCommand = command
        if command == "time" { resultCommand = "time sync" }
        if command == "alarm", let subcommand = arguments.dropFirst().first, ["list", "set", "disable"].contains(subcommand) {
            resultCommand = "alarm " + subcommand
        }
        var target: ResolvedDevice?
        do {
            guard !command.isEmpty else { throw CommandFailure("invalid_arguments", "A command is required.") }
            guard ["list", "brightness", "color", "image", "repl", "connect", "send-hex", "device", "config", "alarm", "time", "countdown", "stopwatch", "animation", "text", "status", "display", "design", "effect"].contains(command), !arguments.contains("--uuid") else {
                throw CommandFailure("unsupported", "Structured output is not supported for this diagnostic command.")
            }
            let options = try CommandOptions(Array(arguments.dropFirst()))
            guard command == "alarm" || !options.hasAlarmWriteOptions else { throw CommandFailure("invalid_arguments", "Schedule and volume options apply only to alarm commands.") }
            guard ["alarm", "status", "display", "design", "effect"].contains(command) || options.queryTimeout == nil else { throw CommandFailure("invalid_arguments", "Query timeout applies only to device queries and live display operations.") }
            guard ["display", "design", "effect"].contains(command) || (options.displayStyle == nil && options.displayColor == nil) else {
                throw CommandFailure("invalid_arguments", "--style and --color are display options.")
            }
            if command == "status" {
                guard options.positionals.isEmpty else { throw CommandFailure("invalid_arguments", "status takes no positional arguments.") }
                guard !options.mock else { throw CommandFailure("unsupported", "Mock mode has no live device status.") }
            }
            let displayOperation = ["display", "design", "effect"].contains(command) ? try DisplayOperation(command: command, options: options) : nil
            try displayOperation?.selection.validate()
            if let displayOperation, !displayOperation.selection.requiresLivePreparation, options.queryTimeout != nil {
                throw CommandFailure("invalid_arguments", "This explicit display profile does not perform a query.")
            }
            guard command == "animation" || (options.resize == nil && !options.adapt) else { throw CommandFailure("invalid_arguments", "--resize and --adapt apply only to animation.") }
            let renderedText = command == "text" ? try prepareText(options) : nil
            let animation = command == "animation" ? try prepareAnimation(options) : renderedText?.upload
            let alarmOperation = command == "alarm" ? try AlarmOperation(options) : nil
            if command == "alarm" {
                guard !options.mock else { throw CommandFailure("unsupported", "Mock mode has no device alarm state; alarm operations require live reads to preserve existing settings.") }
            }
            if command == "device" || command == "config" { try manage(command, options: options); return 0 }
            if command == "list" {
                let devices = try list(options)
                try emit(CommandResult(command: command, status: "ok", data: ["devices": devices]))
                return 0
            }
            guard !options.all, !options.save else { throw CommandFailure("invalid_arguments", "--all and --save are only valid for list.") }
            if command == "repl", options.format != nil { throw CommandFailure("invalid_arguments", "The REPL is interactive; JSON/YAML streams are not supported.") }
            let packet = ["repl", "connect", "alarm", "animation", "text", "status", "display", "design", "effect"].contains(command) ? nil : try packet(command, options: options)
            if command == "connect", !options.positionals.isEmpty { throw CommandFailure("invalid_arguments", "connect takes no positional arguments.") }
            let configuration = try environment.configuration(options.configPath)
            let resolved = try resolve(options, configuration: configuration)
            target = resolved
            if let animation {
                try sendAnimation(animation, to: resolved, options: options)
                try emit(CommandResult(command: command, status: options.mock ? "simulated" : "sent", device: resolved, data: animationData(animation).merging(renderedText.map { ["font": $0.fontName] } ?? [:]) { _, new in new }))
                return 0
            }
            if let operation = displayOperation {
                try emit(performDisplay(operation.selection, command: command, target: resolved, options: options))
                return 0
            }
            if command == "status" {
                try emit(performStatus(target: resolved, options: options))
                return 0
            }
            if let alarmOperation {
                try emit(performAlarm(alarmOperation, target: resolved, options: options))
                return 0
            }
            if command == "repl" { try repl(resolved, options: options); return 0 }
            if command == "connect" {
                let transport = environment.makeTransport(options.mock)
                defer { transport.disconnect() }
                try connect(transport, to: resolved, channel: options.channel)
                try emit(CommandResult(command: command, status: options.mock ? "simulated" : "ok", device: resolved,
                    data: ["channel": transport.channel.map { Int($0) } as Any? ?? NSNull()]))
                return 0
            }
            guard let packet else { throw CommandFailure("invalid_arguments", "A one-shot command is required.") }
            try send(packet, to: resolved, options: options)
            var data: [String: Any] = ["bytes": packet.count]
            switch command {
            case "stopwatch": data["operation"] = options.positionals[0]
            case "countdown": data["operation"] = options.positionals[0]
            case "time": data["operation"] = "sync"
            case "brightness": data["brightness"] = try CommandOptions.percent(options.positionals[0])
            case "color": data["color"] = options.positionals[0].replacingOccurrences(of: "#", with: "").uppercased(); data["brightness"] = options.brightness
            case "image": data["path"] = options.positionals[0]; data["width"] = 16; data["height"] = 16
            case "display": data["selection"] = options.positionals[0]
            case "effect": data["effect"] = Int(options.positionals[0])
            default: break
            }
            try emit(CommandResult(command: command, status: options.mock ? "simulated" : "sent", device: resolved, data: data))
            return 0
        } catch {
            let failure = Self.failure(error)
            environment.errorOutput(failure.message)
            if !["device", "config"].contains(command) {
                do { try emit(CommandResult(command: resultCommand, status: "error", device: target, data: ["code": failure.kind, "message": failure.message])) }
                catch { environment.errorOutput("Cannot encode result: \(error.localizedDescription)") }
            }
            return failure.exitCode
        }
    }

    func emit(_ result: CommandResult) throws {
        if let outputFormat { environment.rawOutput(try result.formatted(outputFormat)) }
    }

    func diagnostic(_ message: String) {
        if outputFormat != nil { environment.errorOutput(message) }
        else { environment.output(message) }
    }

    func resolve(_ options: CommandOptions, configuration: DeviceConfiguration) throws -> ResolvedDevice {
        try DeviceResolver.resolve(name: options.name, address: options.address,
            environmentAddress: environment.variables["TIMEBOX_ADDRESS"], configuration: configuration) {
            try self.environment.discover(options.mock)
        }
    }

    func list(_ options: CommandOptions) throws -> [[String: Any]] {
        guard options.name == nil, options.address == nil, options.positionals.isEmpty,
              options.channel == nil else {
            throw CommandFailure("invalid_arguments", "list does not take a device/name/address selector or channel.")
        }
        let discovered = try environment.discover(options.mock)
        let configuration: DeviceConfiguration
        if options.save {
            configuration = try DeviceConfigFile(path: options.configPath).saveDiscovered(discovered).configuration
            environment.errorOutput("Saved \(configuration.devices.count) device(s) in \(DeviceConfigFile(path: options.configPath).url.path).")
            let path = options.configPath.map { " --config " + Self.shellQuote($0) } ?? ""
            if let name = configuration.defaultName {
                environment.errorOutput("Default: \(name). Change it with: timeboxctl device select \(Self.shellQuote(name))\(path)")
                environment.errorOutput("Rename a logical device with: timeboxctl device rename \(Self.shellQuote(name)) 'new-name'\(path)")
            }
        } else { configuration = try environment.configuration(options.configPath) }
        let devices = discovered.filter { options.all || $0.isTimeboxCandidate }
        if devices.isEmpty, outputFormat == nil { environment.output("No paired Timeboxes found.") }
        return devices.map { device in
            let mac = try? DeviceResolver.canonicalMAC(device.address)
            let name = configuration.devices.keys.first { configuration.devices[$0]?.mac == mac }
            if outputFormat == nil {
                let title = name.map { $0 + " (" + device.name + ")" } ?? device.name
                let emphasized = environment.stdoutIsTerminal && environment.variables["NO_COLOR"] == nil
                    ? "\u{001B}[1m" + title + "\u{001B}[0m" : title
                environment.output("\(emphasized)\n    address: \(device.address)\n    paired: \(device.isPaired ? "yes" : "no")\n    connected: \(device.isConnected ? "yes" : "no")")
            }
            return ["name": name as Any? ?? NSNull(), "mac": mac ?? device.address,
                "bluetooth_name": device.name, "paired": device.isPaired, "connected": device.isConnected,
                "source": device.source.rawValue, "is_timebox": device.isTimeboxCandidate]
        }
    }

    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    func connect(_ transport: CommandTransport, to target: ResolvedDevice, channel: UInt8?) throws {
        diagnostic("Connecting to \(target.logicalName ?? target.device.name) (\(target.device.address))...")
        do { try transport.connect(to: target.device, channel: channel) }
        catch { throw CommandFailure("connection_failed", error.localizedDescription) }
        diagnostic("Connected on RFCOMM channel \(transport.channel.map(String.init) ?? "unknown").")
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
                diagnostic(options.mock ? "Simulated \(packet.count) byte(s)." : "Sent \(packet.count) byte(s).")
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
        case "stopwatch":
            guard options.positionals.count == 1 else { throw CommandFailure("invalid_arguments", "Use stopwatch start, stop or reset.") }
            let action: TimeboxStopwatchAction
            switch options.positionals[0] {
            case "start": action = .start
            case "stop": action = .stop
            case "reset": action = .reset
            default: throw CommandFailure("invalid_arguments", "Use stopwatch start, stop or reset.")
            }
            return try TimeboxPacketEncoder.encode(.stopwatch(action))
        case "countdown":
            if options.positionals == ["stop"] { return try TimeboxPacketEncoder.encode(.stopCountdown) }
            guard options.positionals.count == 2, options.positionals[0] == "start" else { throw CommandFailure("invalid_arguments", "Use countdown start MM:SS or countdown stop.") }
            do { return try TimeboxPacketEncoder.encode(.startCountdown(TimeboxCountdownDuration(options.positionals[1]))) }
            catch { throw CommandFailure("invalid_arguments", error.localizedDescription) }
        case "time":
            guard options.positionals == ["sync"] else { throw CommandFailure("invalid_arguments", "Use time sync.") }
            return try TimeboxPacketEncoder.encode(.synchronizeClock(TimeboxClockSnapshot(date: environment.clock(), timeZone: environment.timeZone())))
        case "display", "design", "effect":
            return try TimeboxPacketEncoder.encode(.display(DisplayOperation(command: command, options: options).selection))
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
        environment.output("Persistent connection open. Commands: target [NAME|current], status, display, design, effect, text MESSAGE, animation PATH [--resize fit|fill|stretch] [--adapt], alarm list/set/disable, time sync, countdown start/stop, stopwatch start/stop/reset, color, brightness, image, hex, help, quit.")
        while true {
            if environment.isInteractive { environment.rawOutput("timebox> ") }
            guard let line = environment.readLine() else { break }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = parts.first?.lowercased() else { continue }
            if ["quit", "exit", "q"].contains(command) { break }
            if ["help", "?"].contains(command) {
                environment.output("target [NAME|current], text MESSAGE, animation PATH [--resize fit|fill|stretch] [--adapt], time sync, countdown start MM:SS, countdown stop, stopwatch start/stop/reset, status [--timeout SECONDS], display clock [--style 0..5], display light [--color RRGGBB] [--brightness 0..100], display design, design 0..2 (fresh capability required), effects unsupported, alarm list, alarm set SLOT --time HH:MM [--days mon,tue] [--volume 0..100], alarm disable SLOT, color RRGGBB [brightness], brightness 0..100, image PATH, hex BYTES, quit")
                continue
            }
            do {
                if command == "text" {
                    let text = try Self.replText(line)
                    let rendered = try TimeboxTextRenderer.render(text)
                    let upload = try TimeboxAnimationEncoder.prepare(rendered.animation)
                    guard transport.isConnected else { throw CommandFailure("connection_failed", "The selected target is disconnected.") }
                    for data in upload.packets { try transport.write(data); transport.wait(milliseconds: 20) }
                    environment.output("Font: " + rendered.fontName)
                    environment.output(options.mock ? "simulated text" : "sent text")
                    continue
                }
                if command == "animation" {
                    let animationOptions = try CommandOptions(Array(parts.dropFirst()))
                    guard animationOptions.name == nil, animationOptions.address == nil, animationOptions.channel == nil,
                          animationOptions.configPath == nil, animationOptions.format == nil, !animationOptions.mock,
                          !animationOptions.all, !animationOptions.save, !animationOptions.hasAlarmWriteOptions,
                          animationOptions.queryTimeout == nil else { throw CommandFailure("invalid_arguments", "Use target NAME to select the REPL device.") }
                    let upload = try prepareAnimation(animationOptions)
                    guard transport.isConnected else { throw CommandFailure("connection_failed", "The selected target is disconnected.") }
                    for data in upload.packets { try transport.write(data); transport.wait(milliseconds: 20) }
                    environment.output(options.mock ? "simulated animation" : "sent animation")
                    continue
                }
                if ["display", "design", "effect"].contains(command) {
                    let displayOptions = try CommandOptions(Array(parts.dropFirst()))
                    guard !displayOptions.hasAlarmWriteOptions,
                          displayOptions.name == nil, displayOptions.address == nil,
                          displayOptions.channel == nil, displayOptions.configPath == nil,
                          displayOptions.format == nil, !displayOptions.mock,
                          !displayOptions.all, !displayOptions.save else {
                        throw CommandFailure("invalid_arguments", "Use target NAME to choose the REPL device; display options configure only the selected display.")
                    }
                    let selection = try DisplayOperation(command: command, options: displayOptions).selection
                    try selection.validate()
                    if selection.requiresLivePreparation {
                        guard !options.mock else { throw CommandFailure("unsupported", "Mock mode has no live display profile or capability state.") }
                        let selectedChannel = transport.channel
                        transport.disconnect()
                        var queryOptions = options
                        queryOptions.queryTimeout = displayOptions.queryTimeout
                        queryOptions.channel = selectedChannel
                        _ = try performDisplay(selection, command: command, target: target, options: queryOptions)
                        transport = environment.makeTransport(false)
                        do { try connect(transport, to: target, channel: selectedChannel) }
                        catch { transport.disconnect(); throw error }
                        transport.wait(milliseconds: 150)
                    } else {
                        guard displayOptions.queryTimeout == nil else { throw CommandFailure("invalid_arguments", "This explicit display profile does not perform a query.") }
                        guard transport.isConnected else { throw CommandFailure("connection_failed", "The selected target is disconnected.") }
                        let packet = try TimeboxPacketEncoder.encode(.display(selection))
                        try transport.write(packet)
                        transport.wait(milliseconds: 60)
                        environment.output(options.mock ? "simulated (\(packet.count) bytes)" : "sent (\(packet.count) bytes)")
                    }
                    continue
                }
                if command == "status" {
                    let statusOptions = try CommandOptions(Array(parts.dropFirst()))
                    guard statusOptions.positionals.isEmpty, !statusOptions.hasAlarmWriteOptions,
                          statusOptions.name == nil, statusOptions.address == nil,
                          statusOptions.channel == nil, statusOptions.configPath == nil,
                          statusOptions.format == nil, !statusOptions.mock,
                          !statusOptions.all, !statusOptions.save else {
                        throw CommandFailure("invalid_arguments", "Use status [--timeout SECONDS]; target NAME selects the REPL device.")
                    }
                    guard !options.mock else { throw CommandFailure("unsupported", "Mock mode has no live device status.") }
                    transport.disconnect()
                    transport.wait(milliseconds: 500)
                    var queryOptions = options
                    queryOptions.queryTimeout = statusOptions.queryTimeout
                    queryOptions.channel = nil
                    _ = try performStatus(target: target, options: queryOptions)
                    transport.wait(milliseconds: 500)
                    transport = environment.makeTransport(false)
                    do { try connect(transport, to: target, channel: nil) }
                    catch { transport.disconnect(); throw error }
                    transport.wait(milliseconds: 150)
                    continue
                }
                if command == "alarm" {
                    let alarmOptions = try CommandOptions(Array(parts.dropFirst()))
                    guard alarmOptions.name == nil,
                          alarmOptions.address == nil, alarmOptions.channel == nil,
                          alarmOptions.configPath == nil, alarmOptions.format == nil,
                          !alarmOptions.mock, !alarmOptions.all, !alarmOptions.save, alarmOptions.displayStyle == nil, alarmOptions.displayColor == nil else {
                        throw CommandFailure("invalid_arguments", "Use alarm list/set/disable; target NAME selects the REPL device.")
                    }
                    let operation = try AlarmOperation(alarmOptions)
                    guard !options.mock else { throw CommandFailure("unsupported", "Mock mode has no device alarm state.") }
                    // A fresh link excludes stale same-opcode replies; resume the
                    // persistent session only after a successful read.
                    transport.disconnect()
                    transport.wait(milliseconds: 500)
                    var queryOptions = options
                    queryOptions.queryTimeout = alarmOptions.queryTimeout
                    queryOptions.channel = nil
                    _ = try performAlarm(operation, target: target, options: queryOptions)
                    transport.wait(milliseconds: 500)
                    transport = environment.makeTransport(options.mock)
                    do { try connect(transport, to: target, channel: nil) }
                    catch { transport.disconnect(); throw error }
                    transport.wait(milliseconds: 150)
                    continue
                }
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
                guard !replOptions.hasAlarmWriteOptions, replOptions.queryTimeout == nil else {
                    throw CommandFailure("invalid_arguments", "Schedule, volume and query timeout options apply only to alarm commands.")
                }
                guard replOptions.resize == nil, !replOptions.adapt else { throw CommandFailure("invalid_arguments", "--resize and --adapt apply only to animation.") }
                guard ["display", "design", "effect"].contains(command) || (replOptions.displayStyle == nil && replOptions.displayColor == nil) else { throw CommandFailure("invalid_arguments", "--style and --color are display options.") }
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
            } catch {
                let failure = Self.failure(error)
                environment.errorOutput("Error: \(failure.message)")
                if command == "target", failure.kind == "device_not_found" {
                    environment.errorOutput("Target unchanged: \(target.logicalName ?? target.device.address).")
                }
            }
        }
        environment.output("Disconnected.")
    }

    static func failure(_ error: Error) -> CommandFailure {
        if let failure = error as? CommandFailure { return failure }
        if let display = error as? TimeboxDisplayError {
            switch display {
            case .invalidDesignIndex: return CommandFailure("invalid_arguments", display.localizedDescription)
            case .incompleteWrite: return CommandFailure("write_failed", display.localizedDescription)
            default: return CommandFailure("unsupported", display.localizedDescription)
            }
        }
        if let alarm = error as? TimeboxAlarmWriteError {
            return CommandFailure("invalid_arguments", alarm.localizedDescription)
        }
        if let query = error as? TimeboxQueryError {
            switch query {
            case .timeout: return CommandFailure("query_timeout", query.localizedDescription)
            case .invalidResponse: return CommandFailure("invalid_response", query.localizedDescription)
            case .unsupported: return CommandFailure("unsupported", query.localizedDescription)
            case .invalidArguments: return CommandFailure("invalid_arguments", query.localizedDescription)
            case .disconnected: return CommandFailure("connection_failed", query.localizedDescription)
            case .cancelled: return CommandFailure("cancelled", query.localizedDescription)
            case .busy: return CommandFailure("query_busy", query.localizedDescription)
            }
        }
        return CommandFailure("execution_failed", error.localizedDescription)
    }
}
