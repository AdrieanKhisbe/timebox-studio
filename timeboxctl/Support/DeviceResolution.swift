import Foundation
import TimeboxBluetooth
import TimeboxKit

public struct CommandFailure: LocalizedError {
    public let kind: String
    public let message: String
    public var exitCode: Int32 { kind == "invalid_arguments" ? 2 : 1 }
    public var errorDescription: String? { message }
    public init(_ kind: String, _ message: String) { self.kind = kind; self.message = message }
}

public struct ConfiguredDevice: Equatable {
    public var mac: String
    public var bluetoothName: String?
    public var model: TimeboxModel?
    public init(mac: String, bluetoothName: String? = nil, model: TimeboxModel? = nil) {
        self.mac = mac; self.bluetoothName = bluetoothName; self.model = model
    }
}

public struct DeviceConfiguration: Equatable {
    public var defaultName: String?
    public var devices: [String: ConfiguredDevice]
    public init(defaultName: String? = nil, devices: [String: ConfiguredDevice] = [:]) {
        self.defaultName = defaultName; self.devices = devices
    }
    public func name(matching name: String) -> String? {
        devices.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

public struct ResolvedDevice {
    public let logicalName: String?
    public let device: TimeboxDevice
    public var modelResolution: TimeboxModelResolution?
    public init(logicalName: String?, device: TimeboxDevice) {
        self.logicalName = logicalName; self.device = device
    }
}

public enum DeviceResolver {
    public static func canonicalMAC(_ value: String) throws -> String {
        let components = value.replacingOccurrences(of: "-", with: ":").split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 6, components.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else {
            throw CommandFailure("invalid_arguments", "Invalid Bluetooth address '\(value)'. Expected AA:BB:CC:DD:EE:FF.")
        }
        return components.map { $0.uppercased() }.joined(separator: ":")
    }

    public static func resolve(name: String?, address: String?, environmentAddress: String?,
                               configuration: DeviceConfiguration,
                               discover: () throws -> [TimeboxDevice]) throws -> ResolvedDevice {
        guard name == nil || address == nil else {
            throw CommandFailure("invalid_arguments", "--device/--name cannot be combined with --address.")
        }
        func configured(_ requested: String) throws -> ResolvedDevice {
            guard let key = configuration.name(matching: requested), let entry = configuration.devices[key] else {
                throw CommandFailure("device_not_found", "Unknown configured device '\(requested)'. Use timeboxctl list --save, then timeboxctl device select.")
            }
            return ResolvedDevice(logicalName: key, device: TimeboxDevice(name: entry.bluetoothName ?? key,
                address: try canonicalMAC(entry.mac), isPaired: false, isConnected: false, source: .bluetooth))
        }
        func byAddress(_ value: String) throws -> ResolvedDevice {
            let mac = try canonicalMAC(value)
            let key = configuration.devices.keys.sorted().first {
                (try? canonicalMAC(configuration.devices[$0]!.mac)) == mac
            }
            return ResolvedDevice(logicalName: key, device: TimeboxDevice(
                name: key.flatMap { configuration.devices[$0]?.bluetoothName } ?? key ?? mac,
                address: mac, isPaired: false, isConnected: false, source: .bluetooth))
        }
        if let name { return try configured(name) }
        if let address { return try byAddress(address) }
        if let value = environmentAddress, !value.isEmpty { return try byAddress(value) }
        if let name = configuration.defaultName { return try configured(name) }
        var seen = Set<String>()
        let devices = try discover().filter { device in
            guard device.isTimeboxCandidate, let mac = try? canonicalMAC(device.address) else { return false }
            return seen.insert(mac).inserted
        }
        guard devices.count == 1, let device = devices.first else {
            throw CommandFailure(devices.isEmpty ? "device_not_found" : "ambiguous_device",
                "Found \(devices.count) paired Timeboxes. Use --address MAC or timeboxctl list --save and timeboxctl device select.")
        }
        return ResolvedDevice(logicalName: nil, device: device)
    }
}
