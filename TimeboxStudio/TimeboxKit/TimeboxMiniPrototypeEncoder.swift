import Foundation

/// THROWAWAY: original 11x11 Timebox Mini experiment, not a supported device profile.
/// Reference: hass-divoom/devices/timeboxmini.py (RGB444) and divoom.py (framing).
/// Kept separate from the Evo encoder so existing 16x16 behavior is unchanged.
public enum TimeboxMiniPrototypeEncoder {
    public static let size = 11

    public static func brightness(_ percent: UInt8) -> Data {
        precondition(percent <= 100)
        return frame(Data([0x74, percent]))
    }

    public static func color(_ color: PixelRGB, brightness: UInt8) -> Data {
        precondition(brightness <= 100)
        return frame(Data([0x45, 0x02, color.red, color.green, color.blue, brightness, 0x00]))
    }

    /// 121 pixels, row-major. Each pair becomes GR / RB / BG nibbles;
    /// the odd final pixel has only two bytes, with its unused red nibble zero.
    public static func image(_ pixels: [PixelRGB]) -> Data {
        precondition(pixels.count == size * size)
        var payload = Data([0x44, 0x00, 0x0A, 0x0A, 0x04])
        for index in stride(from: 0, to: pixels.count, by: 2) {
            let first = pixels[index]
            let second = index + 1 < pixels.count ? pixels[index + 1] : .init(red: 0, green: 0, blue: 0)
            payload.append((first.red >> 4) | (first.green & 0xF0))
            payload.append((first.blue >> 4) | (second.red & 0xF0))
            if index + 1 < pixels.count {
                payload.append((second.green >> 4) | (second.blue & 0xF0))
            }
        }
        return frame(payload)
    }

    /// Length and checksum are computed before byte-stuffing interior bytes.
    public static func frame(_ payload: Data) -> Data {
        precondition(payload.count + 2 <= Int(UInt16.max))
        var interior = TimeboxChecksum.littleEndianBytes(UInt16(payload.count + 2))
        interior.append(payload)
        interior.append(TimeboxChecksum.littleEndianBytes(TimeboxChecksum.sum16(interior)))
        var packet = Data([0x01])
        for byte in interior {
            if (1...3).contains(byte) {
                packet.append(contentsOf: [0x03, byte + 3])
            } else {
                packet.append(byte)
            }
        }
        packet.append(0x02)
        return packet
    }
}
