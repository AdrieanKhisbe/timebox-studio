import Foundation

public enum TimeboxPacketEncoderError: LocalizedError, Equatable {
    case brightnessOutOfRange(Int)
    case payloadTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .brightnessOutOfRange(let value):
            return "Brightness \(value)% is out of range. Use a value from 0 through 100."
        case .payloadTooLarge(let byteCount):
            return "Timebox payload is too large to encode: \(byteCount) byte(s)."
        }
    }
}

public enum TimeboxPacketEncoder {
    public static func encode(_ command: TimeboxCommand) throws -> Data {
        switch command {
        case .display(let display):
            return try encodePayload(display.payload())
        case .raw(let data):
            return data
        case .setBrightness(let percent):
            return try encodeBrightness(percent)
        case let .lightningPlainColor(color, percent):
            return try encodeLightningPlainColor(color: color, brightnessPercent: percent)
        case .image(let frame):
            return try encodePayload(TimeboxImageEncoder.imagePayload(frame: frame))
        case let .setAlarm(current, schedule, volume):
            try validateAlarm(current)
            let desiredVolume = volume ?? current.volume
            guard (0...100).contains(desiredVolume) else {
                throw TimeboxAlarmWriteError.invalidVolume(desiredVolume)
            }
            return try encodePayload(Data([
                0x43, UInt8(current.slot), 1, UInt8(schedule.hour), UInt8(schedule.minute),
                schedule.weekdayMask, current.soundMode, current.triggerMode,
                current.frequencyBytes[0], current.frequencyBytes[1], UInt8(desiredVolume)
            ]))
        case .disableAlarm(let current):
            try validateAlarm(current)
            return try encodePayload(Data([
                0x43, UInt8(current.slot), 0, UInt8(current.hour), UInt8(current.minute),
                current.weekdayMask, current.soundMode, current.triggerMode,
                current.frequencyBytes[0], current.frequencyBytes[1], UInt8(current.volume)
            ]))
        }
    }

    private static func validateAlarm(_ current: TimeboxAlarm) throws {
        guard (0...9).contains(current.slot) else { throw TimeboxAlarmWriteError.invalidSlot(current.slot) }
        guard (0...23).contains(current.hour) else { throw TimeboxAlarmWriteError.invalidHour(current.hour) }
        guard (0...59).contains(current.minute) else { throw TimeboxAlarmWriteError.invalidMinute(current.minute) }
        guard (0...100).contains(current.volume) else { throw TimeboxAlarmWriteError.invalidVolume(current.volume) }
        guard current.frequencyBytes.count == 2 else {
            throw TimeboxAlarmWriteError.invalidFrequencyByteCount(current.frequencyBytes.count)
        }
    }

    /// Implements PROTOCOL.md "Set Brightness".
    /// Payload format: `74 BB`, where `BB` is a 0...100 brightness byte.
    public static func encodeBrightness(_ percent: Int) throws -> Data {
        guard (0...100).contains(percent) else {
            throw TimeboxPacketEncoderError.brightnessOutOfRange(percent)
        }

        return try encodePayload(Data([0x74, UInt8(percent)]))
    }

    /// Implements PROTOCOL.md "Lightning channel" plain color.
    /// Payload format: `45 01 RR GG BB BB TT PP 00 00 00`, where the first
    /// `45 01` selects the lightning channel, `RRGGBB` is the fill color,
    /// `BB` is brightness 0...100, `TT` is `00` (plain color), and `PP` is
    /// `01` (power on). This payload contains literal `0x01` bytes, so it also
    /// confirms whether the protocol needs byte-stuffing (PROTOCOL.md says no).
    public static func encodeLightningPlainColor(color: PixelRGB, brightnessPercent percent: Int) throws -> Data {
        guard (0...100).contains(percent) else {
            throw TimeboxPacketEncoderError.brightnessOutOfRange(percent)
        }

        let payload = Data([
            0x45, 0x01,
            color.red, color.green, color.blue,
            UInt8(percent),
            0x00, // type: plain color
            0x01, // power: on
            0x00, 0x00, 0x00 // fixed trailer
        ])
        return try encodePayload(payload)
    }

    /// Implements PROTOCOL.md "Sending Messages".
    /// Packet format: `01 LLLL PAYLOAD CRCR 02`.
    public static func encodePayload(_ payload: Data) throws -> Data {
        let lengthValue = payload.count + 2
        guard lengthValue <= Int(UInt16.max) else {
            throw TimeboxPacketEncoderError.payloadTooLarge(payload.count)
        }

        let length = TimeboxChecksum.littleEndianBytes(UInt16(lengthValue))
        var checksumInput = Data()
        checksumInput.append(length)
        checksumInput.append(payload)

        var packet = Data([0x01])
        packet.append(length)
        packet.append(payload)
        packet.append(TimeboxChecksum.littleEndianBytes(TimeboxChecksum.sum16(checksumInput)))
        packet.append(0x02)
        return packet
    }
}
