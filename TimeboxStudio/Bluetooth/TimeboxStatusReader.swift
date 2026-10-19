import Foundation
import TimeboxKit

public enum TimeboxStatusReader {
    public static func read(from transport: TimeboxQueryTransport, timeout: TimeInterval = 5,
                            isCancelled: () -> Bool = { false }) throws -> TimeboxStatus {
        try TimeboxQueryReader.read(.status, from: transport, timeout: timeout, isCancelled: isCancelled)
    }

    @MainActor
    public static func read(device: TimeboxDevice, channel: UInt8? = nil,
                            timeout: TimeInterval = 5) async throws -> TimeboxStatus {
        try await TimeboxQueryReader.read(.status, device: device, channel: channel, timeout: timeout)
    }
}
