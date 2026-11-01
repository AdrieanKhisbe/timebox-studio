import Foundation
import TimeboxKit

public struct TimeboxModelResolution: Equatable, Sendable {
    public enum Source: String, Sendable { case explicit, config, detected }
    public let model: TimeboxModel
    public let source: Source
    public init(model: TimeboxModel, source: Source) { self.model = model; self.source = source }
}

/// No name, MAC-prefix or RFCOMM-channel heuristic is treated as model identity.
/// Actual hardware identity is unresolved until a documented, verified signal exists.
public enum TimeboxModelResolver {
    public static func resolve(explicit: TimeboxModel? = nil, saved: TimeboxModel? = nil,
                               bypassSaved: Bool = false, detected: Set<TimeboxModel> = []) throws -> TimeboxModelResolution {
        if let explicit { return .init(model: explicit, source: .explicit) }
        if !bypassSaved, let saved { return .init(model: saved, source: .config) }
        guard detected.count <= 1 else { throw TimeboxModelError.conflicting }
        guard let model = detected.first else { throw TimeboxModelError.unidentified }
        return .init(model: model, source: .detected)
    }
    /// Mock identity is controlled by the application, unlike a renameable Bluetooth name.
    public static func detectedModels(for device: TimeboxDevice) -> Set<TimeboxModel> {
        device == .mock ? [.evo] : []
    }
}
