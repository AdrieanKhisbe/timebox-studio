import Foundation
import TimeboxBluetooth

/// Synchronous CLI boundary; the production adapter services IOBluetooth's main run loop.
public protocol CommandTransport: TimeboxQueryTransport {
    var isConnected: Bool { get }
    var channel: UInt8? { get }
    func connect(to device: TimeboxDevice, channel: UInt8?) throws
    func write(_ packet: Data) throws
    func wait(milliseconds: Int)
    func disconnect()
}

public extension CommandTransport {
    func writeQuery(_ data: Data) throws { try write(data) }
    func waitForQuery(milliseconds: Int) { wait(milliseconds: milliseconds) }
}

public struct CommandEnvironment {
    public var discover: (Bool) throws -> [TimeboxDevice]
    public var configuration: (String?) throws -> DeviceConfiguration
    public var makeTransport: (Bool) -> CommandTransport
    public var output: (String) -> Void
    public var errorOutput: (String) -> Void
    public var rawOutput: (String) -> Void
    public var readLine: () -> String?
    public var isInteractive: Bool
    public var stdoutIsTerminal: Bool
    public var clock: () -> Date
    public var timeZone: () -> TimeZone
    public var variables: [String: String]

    public init(discover: @escaping (Bool) throws -> [TimeboxDevice],
                configuration: @escaping (String?) throws -> DeviceConfiguration = { try DeviceConfigFile(path: $0).read().configuration },
                makeTransport: @escaping (Bool) -> CommandTransport,
                output: @escaping (String) -> Void = { print($0) },
                errorOutput: @escaping (String) -> Void = { fputs($0 + "\n", stderr) },
                rawOutput: @escaping (String) -> Void = { FileHandle.standardOutput.write(Data($0.utf8)) },
                readLine: @escaping () -> String? = { Swift.readLine() },
                isInteractive: Bool = false, stdoutIsTerminal: Bool = false, variables: [String: String] = [:],
                clock: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current }) {
        self.clock = clock; self.timeZone = timeZone
        self.discover = discover; self.configuration = configuration; self.makeTransport = makeTransport
        self.output = output; self.errorOutput = errorOutput; self.readLine = readLine
        self.rawOutput = rawOutput
        self.isInteractive = isInteractive; self.variables = variables
        self.stdoutIsTerminal = stdoutIsTerminal
    }

    public static var live: CommandEnvironment {
        CommandEnvironment(discover: { mock in
            let scan = BluetoothDeviceScanner.scanPairedDevices(includeMock: mock)
            guard !scan.timedOut else { throw CommandFailure("query_timeout", "Paired Bluetooth discovery timed out.") }
            return scan.devices
        }, makeTransport: { mock in
            if mock { return SimulatedCommandTransport() }
            return ClassicCommandTransport()
        }, isInteractive: isatty(STDIN_FILENO) != 0, stdoutIsTerminal: isatty(STDOUT_FILENO) != 0, variables: ProcessInfo.processInfo.environment)
    }
}

private final class SimulatedCommandTransport: CommandTransport {
    var onData: ((Data) -> Void)?
    var isConnected = false
    var channel: UInt8? = 1
    func connect(to device: TimeboxDevice, channel: UInt8?) throws { self.channel = channel ?? 1; isConnected = true }
    func write(_ packet: Data) throws {
        guard isConnected else { throw CommandFailure("connection_failed", "No simulated device is connected.") }
    }
    func wait(milliseconds: Int) {}
    func disconnect() { isConnected = false }
}

private final class ClassicCommandTransport: CommandTransport {
    #if canImport(IOBluetooth)
    private let transport = IOBluetoothTimeboxTransport()
    var onData: ((Data) -> Void)? {
        get { transport.onData }
        set { transport.onData = newValue }
    }
    var isConnected: Bool { transport.isConnected }
    var channel: UInt8? { transport.lastRFCOMMChannelID }
    func connect(to device: TimeboxDevice, channel: UInt8?) throws { try transport.connectPumpingRunLoop(to: device, channelID: channel) }
    func write(_ packet: Data) throws { try transport.writePumpingRunLoop(packet) }
    func wait(milliseconds: Int) { transport.waitPumpingRunLoop(milliseconds: milliseconds) }
    func disconnect() { transport.disconnect() }
    #else
    var onData: ((Data) -> Void)?
    var isConnected: Bool { false }
    var channel: UInt8? { nil }
    func connect(to device: TimeboxDevice, channel: UInt8?) throws { throw TimeboxTransportError.bluetoothUnavailable }
    func write(_ packet: Data) throws { throw TimeboxTransportError.bluetoothUnavailable }
    func wait(milliseconds: Int) {}
    func disconnect() {}
    #endif
}
