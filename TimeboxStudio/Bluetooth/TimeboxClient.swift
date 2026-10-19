import Foundation
import TimeboxKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// High-level entry point for apps built on top of this library.
///
/// Workflow: discover the user's paired Timebox, open a persistent Bluetooth
/// Classic SPP connection, then push images / colors / brightness at any time
/// until `disconnect()`.
///
/// ```swift
/// let client = TimeboxClient()
/// guard let timebox = TimeboxClient.discoverTimeboxes().first else { /* ask user to pair */ }
/// try await client.connect(to: timebox)          // SPP channel auto-resolved from SDP
/// try await client.send(imageAt: "/path/to/art.png")
/// try await client.setBrightness(60)
/// client.disconnect()
/// ```
///
/// The async methods deliver IOBluetooth callbacks on the main run loop, so call
/// them from a context with a running run loop (any AppKit/SwiftUI app). Nothing
/// is hardcoded to a specific device: the Bluetooth address comes from discovery
/// and the RFCOMM channel is resolved per device from its SDP records.
public final class TimeboxClient {
    #if os(macOS)
    private let bluetooth = IOBluetoothTimeboxTransport()
    private var transport: TimeboxTransport { injectedTransport ?? bluetooth }
    #else
    private let bleTransport: TimeboxTransport = CoreBluetoothRCSPTransport()
    private var transport: TimeboxTransport { injectedTransport ?? bleTransport }
    #endif

    private var injectedTransport: TimeboxTransport?
    private var connectedTarget: (device: TimeboxDevice, channel: UInt8?)?
    private var displayTransportFactory: (() -> TimeboxDisplayTransport)?
    public private(set) var modelResolution: TimeboxModelResolution?
    private var requestedModel: TimeboxModel?
    /// Existing callers retain Evo encoding. Pass nil for conservative automatic identification.
    public init(model: TimeboxModel? = .evo) {
        requestedModel = model
        modelResolution = model.map { .init(model: $0, source: .explicit) }
    }
    /// Internal adapters exercise actual library operations without radios.
    convenience init(model: TimeboxModel? = .evo, transport: TimeboxTransport,
                     displayTransportFactory: (() -> TimeboxDisplayTransport)? = nil) {
        self.init(model: model)
        injectedTransport = transport
        self.displayTransportFactory = displayTransportFactory
    }
    private var model: TimeboxModel {
        get throws { guard let value = modelResolution?.model else { throw TimeboxModelError.unidentified }; return value }

    }

    public var isConnected: Bool { transport.isConnected }

    /// Notified when the link unexpectedly drops or auto-reconnects (`true` = connected).
    public var onConnectionChange: ((Bool) -> Void)? {
        get { transport.onConnectionChange }
        set { transport.onConnectionChange = newValue }
    }

    // MARK: - Discovery

    /// All paired Bluetooth devices — present these so the user can pick their
    /// Timebox (the control endpoint is the audio-side device, e.g. `Timebox-Evo-audio`).
    public static func pairedDevices() -> [TimeboxDevice] {
        BluetoothDeviceScanner.scanPairedDevices(includeMock: false).devices
    }

    /// Paired devices whose name looks like a Timebox — a convenience filter over
    /// `pairedDevices()`. The user must have paired the device in macOS first.
    public static func discoverTimeboxes() -> [TimeboxDevice] {
        pairedDevices().filter(\.isTimeboxCandidate)
    }

    // MARK: - Connection

    /// Connect to a discovered device. The SPP RFCOMM channel is auto-resolved
    /// from the device's SDP (pass `channel` only to force a specific one).
    public func connect(to device: TimeboxDevice, channel: UInt8? = nil) async throws {
        let resolved = try TimeboxModelResolver.resolve(explicit: requestedModel, detected: TimeboxModelResolver.detectedModels(for: device))
        #if !os(macOS)
        guard resolved.model != .mini else { throw TimeboxModelError.unsupported("BLE/iOS transport") }
        #endif
        modelResolution = resolved
        #if os(macOS)
        if let channel, injectedTransport == nil {
            try await bluetooth.connect(to: device, channelID: channel)
            connectedTarget = (device, channel)
            return
        }
        #endif
        try await transport.connect(to: device)
        connectedTarget = (device, channel)
    }

    #if os(iOS)
    /// iOS: scan for and connect to the first Timebox advertising over BLE. No pairing
    /// or prior discovery needed — CoreBluetooth finds it by name (or attaches if the
    /// system already holds it connected as a speaker).
    public func connect() async throws {
        try await connect(to: TimeboxDevice(
            name: "Timebox", address: "", isPaired: false, isConnected: false, source: .bluetooth))
    }
    #endif

    /// Connect by Bluetooth address (e.g. `"AA-BB-CC-DD-EE-FF"`). Channel is
    /// auto-resolved unless provided.
    public func connect(address: String, channel: UInt8? = nil) async throws {
        let device = TimeboxDevice(
            name: "Timebox \(address)",
            address: address,
            isPaired: true,
            isConnected: false,
            source: .bluetooth
        )
        try await connect(to: device, channel: channel)
    }

    public func disconnect() {
        connectedTarget = nil
        transport.disconnect()
    }

    // MARK: - Sending (connection must be open)

    /// Select the Mini bare clock or an Evo channel/documented complete profile.
    /// Live-preserving selections close this persistent link, use dedicated fresh
    /// query/write links, then reconnect it. Failure leaves it disconnected.
    /// Receive-capable Classic is required; custom/BLE write adapters are never
    /// silently replaced with a native Classic transport.
    public func display(_ selection: TimeboxDisplay) async throws {
        let selectedModel = try model
        if selectedModel == .mini {
            guard selection == .clock() else { throw TimeboxModelError.unsupported("display channels except bare clock") }
            let packet = try TimeboxPacketEncoder.encode(.display(selection), model: selectedModel)
            try await transport.write(packet)
            return
        }
        try selection.validate()
        if selection.requiresLivePreparation {
            #if os(macOS)
            guard let target = connectedTarget, transport.isConnected else { throw TimeboxTransportError.notConnected }
            guard injectedTransport == nil || displayTransportFactory != nil else { throw TimeboxQueryError.unsupported }
            transport.disconnect()
            do {
                _ = try await TimeboxDisplayWriter.send(selection, device: target.device, channel: target.channel,
                                                       model: try model, makeTransport: displayTransportFactory)
                try await connect(to: target.device, channel: target.channel)
            } catch { disconnect(); throw error }
            return
            #else
            throw TimeboxQueryError.unsupported
            #endif
        }
        try await transport.write(try TimeboxPacketEncoder.encode(.display(selection), model: model))
    }

    /// Display a static image at the selected model’s size.

    public func send(image frame: PixelFrame) async throws {
        try await transport.write(try TimeboxPacketEncoder.encode(.image(frame), model: model))
    }

    #if canImport(CoreGraphics)
    /// Load frame zero, rasterize to the selected model’s size, and display it.
    public func send(imageAt path: String) async throws {
        try await send(image: try ImageToPixelFrameConverter.loadPixelFrame(path: path, model: model))
    }

    /// Rasterize a `CGImage` to the selected model’s size and display it.
    public func send(cgImage: CGImage) async throws {
        try await send(image: try ImageToPixelFrameConverter.pixelFrame(from: cgImage, model: model))
    }
    #endif

    /// Fill the whole display with a single color.
    public func setColor(_ color: PixelRGB, brightnessPercent: Int = 100) async throws {
        try await transport.write(
            try TimeboxPacketEncoder.encode(.lightningPlainColor(color: color, brightnessPercent: brightnessPercent), model: model)
        )
    }

    /// Set the display brightness (0...100).
    public func setBrightness(_ percent: Int) async throws {
        try await transport.write(try TimeboxPacketEncoder.encode(.setBrightness(percent), model: model))
    }

    /// Configure one supplied live alarm slot without changing the device clock.
    /// Read the slot first; sound settings and unspecified volume are preserved.
    public func setAlarm(_ current: TimeboxAlarm, schedule: TimeboxAlarmSchedule, volume: Int? = nil) async throws {
        try await transport.write(try TimeboxPacketEncoder.encode(.setAlarm(current, schedule: schedule, volume: volume), model: model))
    }

    /// Disable one supplied live slot, retaining every other exposed field.
    public func disableAlarm(_ current: TimeboxAlarm) async throws {
        try await transport.write(try TimeboxPacketEncoder.encode(.disableAlarm(current), model: model))
    }

    /// Send one local Gregorian wall-clock snapshot; no ongoing or DST maintenance.
    public func synchronizeClock(at date: Date = Date(), timeZone: TimeZone = .current) async throws {
        let snapshot = try TimeboxClockSnapshot(date: date, timeZone: timeZone)
        try await transport.write(try TimeboxPacketEncoder.encode(.synchronizeClock(snapshot), model: model))
    }

    /// Start the device countdown in the official app's supported range.
    public func startCountdown(_ duration: TimeboxCountdownDuration) async throws {
        try await transport.write(try TimeboxPacketEncoder.encode(.startCountdown(duration), model: model))
    }

    public func stopCountdown() async throws {
        try await transport.write(try TimeboxPacketEncoder.encode(.stopCountdown, model: model))
    }

    /// Control the device stopwatch without a host timer or elapsed-time read claim.
    public func stopwatch(_ action: TimeboxStopwatchAction) async throws {
        try await transport.write(try TimeboxPacketEncoder.encode(.stopwatch(action), model: model))
    }

    /// Prepare the complete upload before writing any bytes; never auto-retry a partial upload.
    public func send(animation: TimeboxAnimation, adapt: Bool = false) async throws -> TimeboxAnimationUpload {
        let upload = try TimeboxAnimationEncoder.prepare(animation, model: model, adapt: adapt)
        for packet in upload.packets {
            try await transport.write(packet)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return upload
    }

    /// Render system-font scrolling text and reuse the animation sender without lossy adaptation.
    public func send(text: String) async throws -> TimeboxAnimationUpload {
        try requireEvo("scrolling text")
        let rendered = try TimeboxTextRenderer.render(text)
        return try await send(animation: rendered.animation)
    }

    private func requireEvo(_ operation: String) throws {
        guard try model == .evo else { throw TimeboxModelError.unsupported(operation) }
    }

    /// Send a raw, already-framed protocol packet (escape hatch).
    public func sendRaw(_ packet: Data) async throws {
        try await transport.write(packet)
    }
}
