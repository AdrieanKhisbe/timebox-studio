import Foundation
import TimeboxKit
import TimeboxBluetooth

extension TimeboxCommandLine {
    func performDisplay(_ selection: TimeboxDisplay, command: String,
                        target: ResolvedDevice, options: CommandOptions) throws -> CommandResult {
        let model = target.modelResolution?.model ?? .evo
        let miniClock = model == .mini && selection == .clock()
        if model == .mini, !miniClock {
            guard case .light = selection else { throw TimeboxModelError.unsupported("this display channel or Evo clock style") }
        }
        if miniClock, options.queryTimeout != nil { throw CommandFailure("invalid_arguments", "Mini clock display does not perform a query.") }
        guard !options.mock || !selection.requiresLivePreparation || miniClock else {
            throw CommandFailure("unsupported", "Live display preservation and design capabilities require device reads; mock state is unavailable.")
        }
        diagnostic("Applying display selection to \(target.logicalName ?? target.device.address)...")
        let result: TimeboxDisplayWriteResult
        do {
            result = try TimeboxDisplayWriter.perform(selection, device: target.device,
            channel: options.channel, timeout: options.queryTimeout ?? 5,
            holdMilliseconds: options.holdMilliseconds, model: target.modelResolution?.model ?? .evo, makeTransport: { environment.makeTransport(options.mock) })
        } catch let error as TimeboxTransportError {
            switch error {
            case .writeFailed: throw CommandFailure("write_failed", error.localizedDescription)
            default: throw CommandFailure("connection_failed", error.localizedDescription)
            }
        }
        diagnostic(options.mock ? "Simulated \(result.packetCount) display packet(s)." : "Sent \(result.packetCount) display packet(s).")
        return CommandResult(command: command, status: options.mock ? "simulated" : "sent", device: target,
            data: ["bytes": result.byteCount, "packets": result.packetCount,
                   "preserved_profile": selection.preservedChannel != nil && !miniClock])
    }
}
