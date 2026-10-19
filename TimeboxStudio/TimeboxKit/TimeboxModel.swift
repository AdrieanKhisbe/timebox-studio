import Foundation

public enum TimeboxModel: String, Codable, CaseIterable, Sendable {
    case evo, mini
    public var width: Int { self == .mini ? 11 : 16 }
    public var height: Int { width }
}

public enum TimeboxModelError: LocalizedError, Equatable {
    case unidentified
    case conflicting
    case unsupported(String)
    public var errorDescription: String? {
        switch self {
        case .unidentified: return "Cannot identify this device reliably. Supply --model evo or --model mini, or save a model override in the config file."
        case .conflicting: return "Conflicting device identity. Supply --model evo or --model mini to override deliberately."
        case .unsupported(let feature): return "Original Timebox Mini does not yet support \(feature) through this library."
        }
    }
}
