import Foundation

/// Clock styles named in the Evo-specific reference. Hardware acceptance is separate.
public enum TimeboxClockStyle: Int, CaseIterable, Codable, Sendable {
    case fullScreen = 0, rainbow, withBox, analogSquare, fullScreenNegative, analogRound
}

/// Historical Evo VJ reference names; current typed operations remain unsupported.
public enum TimeboxEffect: Int, CaseIterable, Codable, Sendable {
    case sparkles = 0, lava, verticalRainbowLines, drops, rainbowSwirl, cmyFade
    case rainbowLava, pastelPatterns, cmyWave, fire, countdown, pinkBlueFade
    case rainbowPolygons, pinkBlueWave, rainbowCross, rainbowShapes
}

public enum TimeboxDisplayError: LocalizedError, Equatable {
    case unverified(String)
    case livePreparationRequired(String)
    case invalidDesignIndex(Int)
    case designCapability(UInt8)
    case incompleteWrite(sent: Int, total: Int, reason: String)
    public var errorDescription: String? {
        switch self {
        case .livePreparationRequired(let operation): return "\(operation) requires fresh device state/capability evidence. Use TimeboxDisplayWriter or the ordinary CLI/REPL command."
        case .invalidDesignIndex(let index): return "Design tab \(index) is outside the app-backed range 0 through 2."
        case .designCapability(let flag): return "Device did not advertise the app's three-tab capability (raw flag \(flag)); no tab packet was sent."
        case let .incompleteWrite(sent, total, reason): return "Transmitted \(sent) of \(total) display packets before failure: \(reason). Visible completion is unverified."
        case .unverified(let operation):
            return "\(operation) is not verified on Evo yet. No display packet was sent. See docs/validation/evo-display-channels.md."
        }
    }
}

public enum TimeboxDisplay: Equatable, Sendable {
    /// An explicit style applies a full white/time-only profile, not a partial edit.
    case clock(style: TimeboxClockStyle? = nil)
    /// An explicit option applies a full plain-light profile: missing color white,
    /// missing brightness100, power on. Bare selection requires a fresh live profile.
    case light(color: PixelRGB? = nil, brightnessPercent: Int? = nil)
    case design(index: Int? = nil)
    case effects(effect: TimeboxEffect? = nil)

    func payload() throws -> Data {
        switch self {
        case .clock(let style):
            guard let style else { throw TimeboxDisplayError.livePreparationRequired("Bare clock selection") }
            // Evo-specific TimeChannel profile: format byte1, time on, other boxes off, white.
            return Data([0x45, 0, 1, UInt8(style.rawValue), 1, 0, 0, 0, 255, 255, 255])
        case let .light(color, brightness):
            guard color != nil || brightness != nil else { throw TimeboxDisplayError.livePreparationRequired("Bare light selection") }
            let percent = brightness ?? 100
            guard (0...100).contains(percent) else { throw TimeboxPacketEncoderError.brightnessOutOfRange(percent) }
            let rgb = color ?? PixelRGB(red: 255, green: 255, blue: 255)
            return Data([0x45, 1, rgb.red, rgb.green, rgb.blue, UInt8(percent), 0, 1, 0, 0, 0])
        case .design(let index):
            guard index == nil else { throw TimeboxDisplayError.livePreparationRequired("Numbered design-tab selection") }
            return Data([0x45, 5])
        case .effects:
            throw TimeboxDisplayError.unverified("Legacy VJ effects on this Evo")
        }
    }
}
