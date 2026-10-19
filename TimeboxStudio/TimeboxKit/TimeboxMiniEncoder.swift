import Foundation

/// Original 11×11 Mini, not MiniToo. RGB444 and OldMode escaped framing.
/// Independent protocol reference: hass-divoom timeboxmini.py / divoom.py.
public enum TimeboxMiniEncoder {
    public static func encode(_ command: TimeboxCommand) throws -> Data {
        switch command {
        case .raw(let bytes): return bytes
        case .setBrightness(let percent):
            try validate(percent)
            return try frame(Data([0x74, UInt8(percent)]))
        case let .lightningPlainColor(color, percent):
            try validate(percent)
            return try frame(Data([0x45, 0x02, color.red, color.green, color.blue, UInt8(percent), 0]))
        case .image(let pixels):
            return try frame(imagePayload(pixels))
        case .setAlarm(let current, _, _), .disableAlarm(let current):
            try TimeboxPacketEncoder.validateAlarm(current, model: .mini)
            // Share all full-record field validation with Evo, then escape OldMode.
            return escapeFrame(try TimeboxPacketEncoder.encode(command, model: .evo))
        case .stopwatch(let action): return try frame(Data([0x45, 6, action.rawValue]))
        case .display(.clock(style: nil)): return try frame(Data([0x45, 0, 1]))
        case .synchronizeClock(let snapshot): return try frame(snapshot.payload)
        case .startCountdown, .stopCountdown: throw TimeboxModelError.unsupported("timers")
        case .display, .displayProfile, .selectDesignTab: throw TimeboxModelError.unsupported("display channels")
        }
    }
    /// Native RGB444 image payload, also reused by Mini animation frame packing.
    static func imagePayload(_ pixels: PixelFrame) throws -> Data {
        guard pixels.width == 11, pixels.height == 11, pixels.pixels.count == 121 else {
            throw PixelFrameError.invalidPixelCount(expected: 121, actual: pixels.pixels.count)
        }
        var payload = Data([0x44, 0x00, 0x0A, 0x0A, 0x04])
        for index in stride(from: 0, to: 121, by: 2) {
            let first = pixels.pixels[index]
            let second = index < 120 ? pixels.pixels[index + 1] : PixelRGB(red: 0, green: 0, blue: 0)
            payload.append((first.red >> 4) | (first.green & 0xF0))
            payload.append((first.blue >> 4) | (second.red & 0xF0))
            if index < 120 { payload.append((second.green >> 4) | (second.blue & 0xF0)) }
        }
        return payload
    }
    private static func validate(_ percent: Int) throws {
        guard (0...100).contains(percent) else { throw TimeboxPacketEncoderError.brightnessOutOfRange(percent) }
    }
    /// The unescaped length and checksum cover the interior, not wire bytes.
    public static func frame(_ payload: Data) throws -> Data {
        escapeFrame(try TimeboxPacketEncoder.encodePayload(payload))
    }
    private static func escapeFrame(_ unescaped: Data) -> Data {
        var packet = Data([0x01])
        for byte in unescaped.dropFirst().dropLast() {
            if (1...3).contains(byte) { packet.append(contentsOf: [0x03, byte + 3]) }
            else { packet.append(byte) }
        }
        packet.append(0x02)
        return packet
    }
}
