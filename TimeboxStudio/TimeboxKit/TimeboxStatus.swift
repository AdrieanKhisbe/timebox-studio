import Foundation

/// Established fields of the manufacturer's 0x46 settings response.
/// The lighting channel's brightness is distinct from system brightness.
public struct TimeboxStatus: Equatable, Sendable {
    /// Selects the model-specific settings layout and configured-channel labels.
    public let model: TimeboxModel
    /// Configured display channel; temporary media overlays may remain visible
    /// without changing this byte. It is not a rendered-pixel/content query.
    public let modeRaw: UInt8
    public let brightness: Int
    public let lightBrightness: Int
    /// Complete response data, including unknown fields/trailing extensions.
    public let rawData: Data

    /// Mode 6 has conflicting source descriptions; preserve it without a label.
    public var mode: String? {
        if model == .mini {
            switch modeRaw {
            case 0: return "clock"
            case 1: return "temperature"
            case 2: return "light"
            case 3: return "special_light"
            case 4: return "sound_light"
            case 5: return "custom"
            default: return nil
            }
        }
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
    case invalidMiniLength(Int)
    case invalidBrightness(field: String, value: Int)
    public var errorDescription: String? {
        switch self {
        case .invalidLength(let count): return "Incomplete Evo settings: expected at least 20 data bytes, received \(count)."
        case .invalidMiniLength(let count): return "Incomplete Mini settings: expected at least 23 data bytes, received \(count)."
        case let .invalidBrightness(field, value): return "Invalid \(field) brightness \(value); expected 0 through 100."
        }
    }
}

public enum TimeboxStatusDecoder {
    public static func decode(_ data: Data) throws -> TimeboxStatus {
        try decode(data, model: .evo)
    }

    public static func decode(_ data: Data, model: TimeboxModel) throws -> TimeboxStatus {
        if model == .mini {
            guard data.count >= 23 else { throw TimeboxStatusDecodingError.invalidMiniLength(data.count) }
        } else {
            guard data.count >= 20 else { throw TimeboxStatusDecodingError.invalidLength(data.count) }
        }
        let bytes = Array(data)
        let light = Int(bytes[6]), system = Int(bytes[model == .mini ? 8 : 10])
        guard light <= 100 else { throw TimeboxStatusDecodingError.invalidBrightness(field: "light", value: light) }
        guard system <= 100 else { throw TimeboxStatusDecodingError.invalidBrightness(field: "system", value: system) }
        return TimeboxStatus(model: model, modeRaw: bytes[0], brightness: system, lightBrightness: light, rawData: data)
    }
}

extension TimeboxQuery where Response == TimeboxStatus {
    public static var status: Self {
        status(model: .evo)
    }
    public static func status(model: TimeboxModel) -> Self {
        try! Self(payload: Data([0x46]), responseCommand: 0x46, model: model,
                  decode: { try TimeboxStatusDecoder.decode($0, model: model) })
    }
}
