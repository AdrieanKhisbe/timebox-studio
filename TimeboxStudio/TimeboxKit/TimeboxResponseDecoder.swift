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

/// Evo NewMode response framing, independently of any query's field meanings.
/// Retains partial frames; never treats an incomplete frame as an empty result.
public struct TimeboxResponseDecoder {
    private var buffer = Data()
    public init() {}
    public var hasPendingBytes: Bool { !buffer.isEmpty }

    public mutating func append(_ data: Data) throws -> [TimeboxResponseFrame] {
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
