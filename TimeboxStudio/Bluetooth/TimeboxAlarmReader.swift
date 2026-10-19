import Foundation
import TimeboxKit

public enum TimeboxAlarmReader {
    /// Uses the shared verified-response query path and closes the dedicated link.
    public static func read(from transport: TimeboxQueryTransport, model: TimeboxModel = .evo, timeout: TimeInterval = 5,
                            isCancelled: () -> Bool = { false }) throws -> [TimeboxAlarm] {
        try TimeboxQueryReader.read(.alarms(model: model), from: transport, timeout: timeout, isCancelled: isCancelled)
    }

    /// Swift app entry point. A dedicated connection is opened and closed for
    /// this read; it must not compete with another controller's open RFCOMM link.
    @MainActor
    public static func read(device: TimeboxDevice, channel: UInt8? = nil,
                            model: TimeboxModel = .evo, timeout: TimeInterval = 5) async throws -> [TimeboxAlarm] {
        try await TimeboxQueryReader.read(.alarms(model: model), device: device, channel: channel, timeout: timeout)
    }
}
