import Foundation
import TimeboxKit

public enum TimeboxStatusReader {
    public static func read(from transport: TimeboxQueryTransport, timeout: TimeInterval = 5,
                            isCancelled: () -> Bool = { false }) throws -> TimeboxStatus {
        try read(from: transport, model: .evo, timeout: timeout, isCancelled: isCancelled)
    }

    public static func read(from transport: TimeboxQueryTransport, model: TimeboxModel,
                            timeout: TimeInterval = 5, isCancelled: () -> Bool = { false }) throws -> TimeboxStatus {
        try TimeboxQueryReader.read(.status(model: model), from: transport, timeout: timeout, isCancelled: isCancelled)
    }

    @MainActor
    public static func read(device: TimeboxDevice, channel: UInt8? = nil,
                            timeout: TimeInterval = 5) async throws -> TimeboxStatus {
        try await read(device: device, channel: channel, model: .evo, timeout: timeout)
    }

    @MainActor
    public static func read(device: TimeboxDevice, channel: UInt8? = nil, model: TimeboxModel,
                            timeout: TimeInterval = 5) async throws -> TimeboxStatus {
        try await TimeboxQueryReader.read(.status(model: model), device: device, channel: channel, timeout: timeout)
    }
}
