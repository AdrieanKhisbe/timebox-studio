import Foundation

/// Established fields of the manufacturer's 0x46 settings response.
/// The lighting channel's brightness is distinct from system brightness.
public struct TimeboxStatus: Equatable, Sendable {
    public let modeRaw: UInt8
    public let brightness: Int
    public let lightBrightness: Int
    /// Complete response data, including unknown fields/trailing extensions.
    public let rawData: Data

    /// Mode 6 has conflicting source descriptions; preserve it without a label.
    public var mode: String? {
        switch modeRaw {
        case 0: return "clock"
        case 1: return "light"
        case 2: return "divoom"
        case 3: return "vj"
        case 4: return "music"
        case 5: return "custom"
        default: return nil
        }
    }
}

public enum TimeboxStatusDecodingError: LocalizedError, Equatable {
    case invalidLength(Int)
    case invalidBrightness(field: String, value: Int)
    public var errorDescription: String? {
        switch self {
        case .invalidLength(let count): return "Incomplete Evo settings: expected at least 20 data bytes, received \(count)."
        case let .invalidBrightness(field, value): return "Invalid Evo \(field) brightness \(value); expected 0 through 100."
        }
    }
}

public enum TimeboxStatusDecoder {
    public static func decode(_ data: Data) throws -> TimeboxStatus {
        guard data.count >= 20 else { throw TimeboxStatusDecodingError.invalidLength(data.count) }
        let bytes = Array(data)
        let light = Int(bytes[6]), system = Int(bytes[10])
        guard light <= 100 else { throw TimeboxStatusDecodingError.invalidBrightness(field: "light", value: light) }
        guard system <= 100 else { throw TimeboxStatusDecodingError.invalidBrightness(field: "system", value: system) }
        return TimeboxStatus(modeRaw: bytes[0], brightness: system, lightBrightness: light, rawData: data)
    }
}

extension TimeboxQuery where Response == TimeboxStatus {
    public static var status: Self {
        Self(request: Data([1, 3, 0, 0x46, 0x49, 0, 2]), responseCommand: 0x46,
             decode: TimeboxStatusDecoder.decode)
    }
}
