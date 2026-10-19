import Foundation

public struct TimeboxDesignCapabilities: Equatable, Sendable {
    public let rawFlag: UInt8
    public var supportsThreeTabs: Bool { rawFlag == 1 }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count == 2, data.first == 0x18 else {
            throw TimeboxResponseError.malformed("Expected exact BD18 capability flag reply")
        }
        return Self(rawFlag: data[data.startIndex + 1])
    }
}

extension TimeboxQuery where Response == TimeboxDesignCapabilities {
    /// Actual app CmdManager.U0; parent captured reply18 01 on the Evo.
    public static var designCapabilities: Self {
        // Empty/matching-selector malformed data must fail decoding, not disappear
        // as unrelated noise. A valid different BD selector is ignored.
        try! Self(payload: Data([0xBD, 0x18]), responseCommand: 0xBD,
            matchingResponse: { $0.isEmpty || $0.first == 0x18 }, decode: TimeboxDesignCapabilities.decode)
    }
}

/// An existing target channel's complete stored profile, not a guessed default.
/// Unknown current mode/style/effect IDs need not prevent byte-preserving switching;
/// unrecognized layouts and invalid boolean fields are rejected before writes.
public struct TimeboxDisplayProfile: Equatable, Sendable {
    public enum Channel: Sendable { case clock, light }
    let payload: Data
    public init(channel: Channel, status: TimeboxStatus) throws {
        guard status.model == .evo else { throw TimeboxModelError.unsupported("Evo display profile preservation") }
        let bytes = Array(status.rawData)
        guard bytes.count == 20 else {
            throw TimeboxDisplayError.unverified("Preservation of unknown settings-layout extensions")
        }
        switch channel {
        case .clock:
            guard bytes[11] <= 1, bytes[16...19].allSatisfy({ $0 <= 1 }) else {
                throw TimeboxDisplayError.unverified("Preservation of unknown clock flag values")
            }
            payload = Data([0x45, 0, bytes[11], bytes[15]] + Array(bytes[16...19]) + Array(bytes[12...14]))
        case .light:
            guard bytes[8] <= 1 else { throw TimeboxDisplayError.unverified("Preservation of unknown light power flag") }
            payload = Data([0x45, 1] + Array(bytes[3...8]) + [0, 0, 0])
        }
    }
}

extension TimeboxDisplay {
    /// Only these selections require fresh live state/capability evidence.
    public var requiresLivePreparation: Bool {
        switch self {
        case .clock(style: nil), .light(color: nil, brightnessPercent: nil): return true
        case .design(let index): return index != nil
        default: return false
        }
    }
    public var preservedChannel: TimeboxDisplayProfile.Channel? {
        switch self {
        case .clock(style: nil): return .clock
        case .light(color: nil, brightnessPercent: nil): return .light
        default: return nil
        }
    }
    /// Validate pure inputs and full explicit packets before query/connection I/O.
    public func validate() throws {
        if case .design(let index?) = self {
            guard (0...2).contains(index) else { throw TimeboxDisplayError.invalidDesignIndex(index) }
        } else if !requiresLivePreparation { _ = try payload() }
    }
}
