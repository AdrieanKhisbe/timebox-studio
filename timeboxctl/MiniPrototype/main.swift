// THROWAWAY PROTOTYPE. Question: can the original Mini's encoder reuse our Classic transport?
// No config writes or default-device inference. Dry-run unless --send is explicit.
import Foundation
import CoreGraphics
import ImageIO
import TimeboxBluetooth
import TimeboxKit
import TimeboxUtilities

let usage = """
THROWAWAY Timebox Mini prototype (11x11, RGB444, escaped Classic packets)
  timeboxmini-prototype brightness 30
  timeboxmini-prototype color FF0000 [--brightness 30]
  timeboxmini-prototype image picture.png
  timeboxmini-prototype pattern
  timeboxmini-prototype demo

Dry-run by default: prints state and wire bytes without Bluetooth access.
To send: append --send --name "Bluetooth name" OR --send --address AA:BB:CC:DD:EE:FF
Channel defaults to 4 (Mini reference); override with --channel 1..30 or --channel auto.
demo sends brightness, red, then an orientation pattern over one connection.
No alarms, persistence, BLE, animation, or production Mini support is implied.
"""

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

func parseColor(_ text: String) -> PixelRGB {
    let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
        fail("Expected six hex digits, e.g. FF0000")
    }
    return PixelRGB(red: UInt8((value >> 16) & 255), green: UInt8((value >> 8) & 255), blue: UInt8(value & 255))
}

func percent(_ value: String) -> UInt8 {
    guard let result = UInt8(value), result <= 100 else { fail("Brightness must be 0...100") }
    return result
}

func loadPixels(_ path: String) -> [PixelRGB] {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("Cannot load image: \(path)") }
    let size = TimeboxMiniPrototypeEncoder.size
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    let created = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.interpolationQuality = .none
        // Match the current static converter: stretch first frame; alpha over black.
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return true
    }
    guard created else { fail("Cannot create 11x11 drawing context") }
    return stride(from: 0, to: bytes.count, by: 4).map {
        PixelRGB(red: bytes[$0], green: bytes[$0 + 1], blue: bytes[$0 + 2])
    }
}

func orientationPattern() -> [PixelRGB] {
    let size = TimeboxMiniPrototypeEncoder.size
    return (0..<(size * size)).map { index in
        let x = index % size, y = index / size
        if x == 0 && y == 0 { return PixelRGB(red: 255, green: 255, blue: 255) }
        if x == size - 1 && y == size - 1 { return PixelRGB(red: 0, green: 0, blue: 255) }
        if y == 0 { return PixelRGB(red: 255, green: 0, blue: 0) }
        if x == 0 { return PixelRGB(red: 0, green: 255, blue: 0) }
        if x == y { return PixelRGB(red: 255, green: 255, blue: 0) }
        return PixelRGB(red: 0, green: 0, blue: 0)
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { print(usage); exit(0) }
arguments.removeFirst()
if command == "--help" || command == "help" { print(usage); exit(0) }
var positionals: [String] = []
var options: [String: String] = [:]
var send = false
while !arguments.isEmpty {
    let value = arguments.removeFirst()
    if value == "--send" { send = true }
    else if ["--name", "--address", "--channel", "--brightness"].contains(value) {
        guard !arguments.isEmpty else { fail("Missing value for \(value)") }
        options[value] = arguments.removeFirst()
    } else if value.hasPrefix("--") { fail("Unknown option: \(value)") }
    else { positionals.append(value) }
}
guard !(options["--name"] != nil && options["--address"] != nil) else {
    fail("Choose --name or --address, not both")
}
let channelText = options["--channel"] ?? "4"
let channel: UInt8?
if channelText == "auto" { channel = nil }
else if let number = UInt8(channelText), (1...30).contains(number) { channel = number }
else { fail("Channel must be 1...30 or auto") }
let brightness = percent(options["--brightness"] ?? "30")
var packets: [(String, Data)] = []
switch command {
case "brightness":
    guard positionals.count == 1 else { fail("brightness needs one percentage") }
    let value = percent(positionals[0])
    packets = [("brightness \(value)%", TimeboxMiniPrototypeEncoder.brightness(value))]
case "color":
    guard positionals.count == 1 else { fail("color needs one RGB value") }
    packets = [("color \(positionals[0]), brightness \(brightness)%", TimeboxMiniPrototypeEncoder.color(parseColor(positionals[0]), brightness: brightness))]
case "image":
    guard positionals.count == 1 else { fail("image needs one path") }
    packets = [("image \(positionals[0]), 11x11 stretched first frame, RGB444", TimeboxMiniPrototypeEncoder.image(loadPixels(positionals[0])))]
case "pattern", "demo":
    guard positionals.isEmpty else { fail("\(command) takes no positional arguments") }
    if command == "demo" {
        packets.append(("brightness 30%", TimeboxMiniPrototypeEncoder.brightness(30)))
        packets.append(("red, brightness 30%", TimeboxMiniPrototypeEncoder.color(parseColor("FF0000"), brightness: 30)))
    }
    packets.append(("11x11 pattern: white top-left; red top; green left; yellow diagonal; blue bottom-right", TimeboxMiniPrototypeEncoder.image(orientationPattern())))
default: fail("Unknown command: \(command)\n\(usage)")
}

print("PROTOTYPE: original Timebox Mini; 11x11 RGB444; escaped framing; \(send ? "SEND" : "DRY RUN")")
print("Channel: \(channel.map(String.init) ?? "SDP automatic"); selector: \(options["--name"] ?? options["--address"] ?? "none")")
for (label, packet) in packets {
    print("\(label) -> \(packet.count) wire bytes\n\(HexDump.string(from: packet))")
}
guard send else { print("No Bluetooth connection or writes performed."); exit(0) }

let discovered = BluetoothDeviceScanner.scanPairedDevices()
guard !discovered.timedOut else { fail("Bluetooth discovery timed out") }
let normalize: (String) -> String = { $0.lowercased().replacingOccurrences(of: "-", with: ":") }
let matches: [TimeboxDevice]
if let name = options["--name"] {
    matches = discovered.devices.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
} else if let address = options["--address"] {
    matches = discovered.devices.filter { normalize($0.address) == normalize(address) }
} else { fail("--send requires an explicit paired --name or --address") }
guard matches.count == 1, let device = matches.first else {
    fail("Expected exactly one paired target, found \(matches.count). Use an explicit unique address.")
}
print("Target: \(device.name) [\(device.address)]")
let transport = IOBluetoothTimeboxTransport()
do {
    try transport.connectPumpingRunLoop(to: device, channelID: channel)
    print("Connected: RFCOMM channel \(transport.lastRFCOMMChannelID.map(String.init) ?? "unknown")")
    transport.waitPumpingRunLoop(milliseconds: 200)
    for (label, packet) in packets {
        try transport.writePumpingRunLoop(packet)
        print("Sent: \(label). Visual effect is not confirmed by this write callback.")
        transport.waitPumpingRunLoop(milliseconds: command == "demo" ? 2000 : 1000)
    }
    transport.disconnect()
    print("Disconnected. Prototype verdict still requires physical observation.")
} catch {
    transport.disconnect()
    fail("Prototype transport failed: \(error.localizedDescription)")
}
