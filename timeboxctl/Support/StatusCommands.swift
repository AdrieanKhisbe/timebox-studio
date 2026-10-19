import Foundation
import TimeboxKit
import TimeboxBluetooth

extension TimeboxCommandLine {
    func performStatus(target: ResolvedDevice, options: CommandOptions) throws -> CommandResult {
        let model = target.modelResolution?.model ?? .evo
        guard !options.mock else { throw CommandFailure("unsupported", "Mock mode has no live device status.") }
        let transport = environment.makeTransport(false)
        defer { transport.disconnect() }
        try connect(transport, to: target, channel: options.channel)
        transport.wait(milliseconds: 150)
        let status: TimeboxStatus
        do { status = try TimeboxStatusReader.read(from: transport, model: model, timeout: options.queryTimeout ?? 5) }
        catch let error as TimeboxQueryError { throw Self.failure(error) }
        catch { throw CommandFailure("write_failed", error.localizedDescription) }
        if outputFormat == nil {
            let mode = status.mode.map { "\($0) (\(status.modeRaw))" } ?? "unknown (\(status.modeRaw))"
            environment.output("Configured channel: \(mode); system brightness: \(status.brightness)%; light brightness: \(status.lightBrightness)%.")
        }
        return CommandResult(command: "status", status: "ok", device: target, data: [
            "mode": status.mode as Any? ?? NSNull(), "mode_raw": Int(status.modeRaw),
            "brightness": status.brightness, "light_brightness": status.lightBrightness,
            "raw_data": status.rawData.map { Int($0) }
        ])
    }
}
