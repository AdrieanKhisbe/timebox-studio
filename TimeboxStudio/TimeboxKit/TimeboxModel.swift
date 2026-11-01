import Foundation

public enum TimeboxProtocolFamily: String, Codable, CaseIterable, Sendable {
    case legacy11, evo16
    public var width: Int { self == .legacy11 ? 11 : 16 }
}

public enum TimeboxModel: String, Codable, CaseIterable, Sendable {
    case evo, mini, timebox
    public var protocolFamily: TimeboxProtocolFamily { self == .evo ? .evo16 : .legacy11 }
    public var width: Int { protocolFamily.width }
    public var height: Int { width }
    // Three records were read on both AKTBR (Mini) and the original TimeBox-audio.
    public var alarmSlotCount: Int { self == .evo ? 10 : 3 }
}

public enum TimeboxModelError: LocalizedError, Equatable {
    case unidentified
    case conflicting
    case unsupported(String)
    public var errorDescription: String? {
        switch self {
        case .unidentified: return "Cannot identify this device reliably. Supply --model evo, --model mini or --model timebox, or save a model override in the config file."
        case .conflicting: return "Conflicting device identity. Supply --model evo, --model mini or --model timebox to override deliberately."
        case .unsupported(let feature): return "This device does not yet support \(feature) through this library."
        }
    }
}
