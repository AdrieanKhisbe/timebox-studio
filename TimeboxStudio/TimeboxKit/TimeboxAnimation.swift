import Foundation

public enum TimeboxAnimationError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let reason) = self { return reason }; return nil }
}

public struct TimeboxAnimationFrame: Equatable, Sendable {
    public let image: PixelFrame
    public let durationMilliseconds: Int
    public init(image: PixelFrame, durationMilliseconds: Int) throws {
        guard image.pixels.count == 256, durationMilliseconds > 0 else {
            throw TimeboxAnimationError.invalid("Animation frames require 256 pixels and a positive millisecond duration.")
        }
        self.image = image; self.durationMilliseconds = durationMilliseconds
    }
}

/// A bounded host-side animation, before device upload preparation.
public struct TimeboxAnimation: Equatable, Sendable {
    public let frames: [TimeboxAnimationFrame]
    public init(frames: [TimeboxAnimationFrame]) throws {
        guard !frames.isEmpty, frames.count <= 2048 else {
            throw TimeboxAnimationError.invalid("Animation input must contain 1...2048 frames (host resource limit).")
        }
        guard frames.allSatisfy({ $0.durationMilliseconds <= 86_400_000 }) else {
            throw TimeboxAnimationError.invalid("A source frame exceeds the host duration limit of one day.")
        }
        self.frames = frames
    }
    public var totalMilliseconds: Int { frames.reduce(0) { $0 + $1.durationMilliseconds } }
}

public struct TimeboxAnimationUpload: Sendable {
    public let packets: [Data]
    public let sourceFrames: Int
    public let effectiveFrames: Int
    public let sourceMilliseconds: Int
    public let effectiveMilliseconds: Int
    public let paletteBits: Int
    public var adapted: Bool { paletteBits < 8 || sourceFrames != effectiveFrames || sourceMilliseconds != effectiveMilliseconds }
}

public enum TimeboxAnimationEncoder {
    /// 200 binary bytes per chunk, 8-bit sequence: representational limits of legacy 0x49.
    public static let maximumStreamBytes = 200 * 256
    public static let maximumFrameMilliseconds = 65535

    public static func prepare(_ animation: TimeboxAnimation, adapt: Bool = false) throws -> TimeboxAnimationUpload {
        var candidates = animation.frames
        func framesData(_ frames: [TimeboxAnimationFrame], bits: Int) throws -> Data {
            var result = Data()
            for frame in frames {
                guard (1...maximumFrameMilliseconds).contains(frame.durationMilliseconds) else {
                    throw TimeboxAnimationError.invalid("Frame timing must fit 1...65535 ms; use --adapt to split longer holds.")
                }
                var image = frame.image
                if bits < 8 {
                    let mask = UInt8(255 << (8 - bits) & 255)
                    image.pixels = image.pixels.map { PixelRGB(red: $0.red & mask, green: $0.green & mask, blue: $0.blue & mask) }
                }
                // Same per-frame palette/reset/indices as static images; replace static delay.
                var data = Data(TimeboxImageEncoder.imagePayload(frame: image).dropFirst(5))
                data[3] = UInt8(frame.durationMilliseconds & 255)
                data[4] = UInt8(frame.durationMilliseconds >> 8)
                result.append(data)
                if result.count > maximumStreamBytes { break }
            }
            return result
        }
        if adapt {
            var split: [TimeboxAnimationFrame] = []
            for frame in candidates {
                var remaining = frame.durationMilliseconds
                while remaining > 0 {
                    let duration = min(remaining, maximumFrameMilliseconds)
                    guard split.count < 2048 else { throw TimeboxAnimationError.invalid("Timing adaptation exceeds the host frame limit.") }
                    split.append(try TimeboxAnimationFrame(image: frame.image, durationMilliseconds: duration))
                    remaining -= duration
                }
            }
            candidates = split
        }
        var bits = 8
        var stream = try framesData(candidates, bits: bits)
        if adapt {
            while stream.count > maximumStreamBytes, bits > 1 {
                bits -= 1
                stream = try framesData(candidates, bits: bits)
            }
            // Merge adjacent time buckets, retaining the first image. Preserve total duration.
            while stream.count > maximumStreamBytes, candidates.count > 1 {
                var reduced: [TimeboxAnimationFrame] = []
                var index = 0
                var changed = false
                while index < candidates.count {
                    let first = candidates[index]
                    if index + 1 < candidates.count,
                       first.durationMilliseconds + candidates[index + 1].durationMilliseconds <= maximumFrameMilliseconds {
                        reduced.append(try TimeboxAnimationFrame(image: first.image, durationMilliseconds: first.durationMilliseconds + candidates[index + 1].durationMilliseconds))
                        index += 2; changed = true
                    } else { reduced.append(first); index += 1 }
                }
                guard changed else { break }
                candidates = reduced
                stream = try framesData(candidates, bits: bits)
            }
        }
        guard stream.count <= maximumStreamBytes else {
            throw TimeboxAnimationError.invalid("Animation exceeds the 51200-byte legacy upload envelope; use --adapt or shorten the input.")
        }
        var packets: [Data] = []
        for offset in stride(from: 0, to: stream.count, by: 200) {
            var payload = Data([0x49, UInt8(stream.count & 255), UInt8(stream.count >> 8), UInt8(offset / 200)])
            payload.append(stream[offset..<min(offset + 200, stream.count)])
            packets.append(try TimeboxPacketEncoder.encodePayload(payload))
        }
        return TimeboxAnimationUpload(packets: packets, sourceFrames: animation.frames.count,
            effectiveFrames: candidates.count, sourceMilliseconds: animation.totalMilliseconds,
            effectiveMilliseconds: candidates.reduce(0) { $0 + $1.durationMilliseconds }, paletteBits: bits)
    }
}
