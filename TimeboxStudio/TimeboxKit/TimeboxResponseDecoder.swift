import Foundation

public struct TimeboxResponseFrame: Equatable, Sendable {
    public let command: UInt8
    public let data: Data
}

public enum TimeboxResponseError: LocalizedError, Equatable {
    case malformed(String)
    public var errorDescription: String? {
        switch self { case .malformed(let reason): return "Invalid device response: \(reason)." }
    }
}

/// Model-specific response framing, independently of any query’s field meanings.
/// Retains partial frames; never treats an incomplete frame as an empty result.
public struct TimeboxResponseDecoder {
    private var buffer = Data()
    private let model: TimeboxModel
    public init(model: TimeboxModel = .evo) { self.model = model }
    public var hasPendingBytes: Bool { !buffer.isEmpty }

    public mutating func append(_ data: Data) throws -> [TimeboxResponseFrame] {
        if model == .mini { return try appendMini(data) }
        return try appendEvo(data)
    }

    private mutating func appendMini(_ data: Data) throws -> [TimeboxResponseFrame] {
        buffer.append(data)
        var frames: [TimeboxResponseFrame] = []
        let greeting: [UInt8] = [0, 5, 0x48, 0x45, 0x4C, 0x4C, 0x4F, 0]
        while !buffer.isEmpty {
            let bytes = [UInt8](buffer)
            if bytes[0] == 0 {
                let count = min(bytes.count, greeting.count)
                guard Array(bytes.prefix(count)) == Array(greeting.prefix(count)) else {
                    throw TimeboxResponseError.malformed("unrecognized Mini greeting")
                }
                guard bytes.count >= greeting.count else { break }
                buffer = Data(bytes.dropFirst(greeting.count))
                continue
            }
            guard bytes[0] == 1 else { throw TimeboxResponseError.malformed("missing Mini start byte") }
            var interior: [UInt8] = []
            var index = 1
            var complete = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 2 {
                    var decoder = TimeboxResponseDecoder(model: .evo)
                    let decoded = try decoder.append(Data([1] + interior + [2]))
                    guard decoded.count == 1, !decoder.hasPendingBytes else {
                        throw TimeboxResponseError.malformed("truncated Mini frame")
                    }
                    frames.append(contentsOf: decoded)
                    buffer = Data(bytes.dropFirst(index + 1))
                    complete = true
                    break
                }
                if byte == 1 { throw TimeboxResponseError.malformed("unescaped Mini start byte") }
                if byte == 3 {
                    guard index + 1 < bytes.count else { break }
                    let escaped = bytes[index + 1]
                    guard (4...6).contains(escaped) else { throw TimeboxResponseError.malformed("invalid Mini escape") }
                    interior.append(escaped - 3)
                    index += 2
                } else {
                    interior.append(byte)
                    index += 1
                }
                if interior.count >= 2 {
                    let length = Int(interior[0]) | Int(interior[1]) << 8
                    guard length >= 5 else { throw TimeboxResponseError.malformed("Mini response length is too short") }
                    guard interior.count <= length + 2 else { throw TimeboxResponseError.malformed("Mini frame exceeds declared length") }
                }
            }
            if !complete { break }
        }
        return frames
    }

    private mutating func appendEvo(_ data: Data) throws -> [TimeboxResponseFrame] {
        buffer.append(data)
        var frames: [TimeboxResponseFrame] = []
        while !buffer.isEmpty {
            let bytes = [UInt8](buffer)
            guard bytes[0] == 1 else { throw TimeboxResponseError.malformed("missing start byte") }
            guard bytes.count >= 3 else { break }
            let length = Int(bytes[1]) | Int(bytes[2]) << 8
            guard length >= 5 else { throw TimeboxResponseError.malformed("response length is too short") }
            guard bytes.count >= length + 4 else { break }
            guard bytes[length + 3] == 2 else { throw TimeboxResponseError.malformed("missing end byte") }
            let checksum = UInt16(bytes[length + 1]) | UInt16(bytes[length + 2]) << 8
            guard TimeboxChecksum.sum16(Data(bytes[1..<(length + 1)])) == checksum else {
                throw TimeboxResponseError.malformed("checksum mismatch")
            }
            guard bytes[3] == 4, bytes[5] == 0x55 else {
                throw TimeboxResponseError.malformed("unrecognized response envelope")
            }
            frames.append(TimeboxResponseFrame(command: bytes[4], data: Data(bytes[6..<(length + 1)])))
            buffer = Data(bytes.dropFirst(length + 4))
        }
        return frames
    }
}
