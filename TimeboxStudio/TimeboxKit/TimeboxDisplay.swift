import Foundation

/// Clock styles named in the Evo-specific reference. Hardware acceptance is separate.
public enum TimeboxClockStyle: Int, CaseIterable, Codable, Sendable {
    case fullScreen = 0, rainbow, withBox, analogSquare, fullScreenNegative, analogRound
}

/// Evo-specific VJ effect catalogue; no arbitrary byte-sized ID range is accepted.
public enum TimeboxEffect: Int, CaseIterable, Codable, Sendable {
    case sparkles = 0, lava, verticalRainbowLines, drops, rainbowSwirl, cmyFade
    case rainbowLava, pastelPatterns, cmyWave, fire, countdown, pinkBlueFade
    case rainbowPolygons, pinkBlueWave, rainbowCross, rainbowShapes
}

public enum TimeboxDisplayError: LocalizedError, Equatable {
    case unverified(String)
    public var errorDescription: String? {
        switch self { case .unverified(let operation):
            return "\(operation) is not verified on Evo yet. No display packet was sent. See docs/validation/evo-display-channels.md."
        }
    }
}

public enum TimeboxDisplay: Equatable, Sendable {
    /// An explicit style applies a full white/time-only profile, not a partial edit.
    case clock(style: TimeboxClockStyle? = nil)
    /// An explicit option applies a full plain-light profile: missing color white,
    /// missing brightness100, power on. Bare selection awaits preservation evidence.
    case light(color: PixelRGB? = nil, brightnessPercent: Int? = nil)
    case design(index: Int? = nil)
    case effects(effect: TimeboxEffect? = nil)

    func payload() throws -> Data {
        switch self {
        case .clock(let style):
            guard let style else { throw TimeboxDisplayError.unverified("Bare clock selection with existing-settings preservation") }
            // Evo-specific TimeChannel profile: format byte1, time on, other boxes off, white.
            return Data([0x45, 0, 1, UInt8(style.rawValue), 1, 0, 0, 0, 255, 255, 255])
        case let .light(color, brightness):
            guard color != nil || brightness != nil else { throw TimeboxDisplayError.unverified("Bare light selection with existing-settings preservation") }
            let percent = brightness ?? 100
            guard (0...100).contains(percent) else { throw TimeboxPacketEncoderError.brightnessOutOfRange(percent) }
            let rgb = color ?? PixelRGB(red: 255, green: 255, blue: 255)
            return Data([0x45, 1, rgb.red, rgb.green, rgb.blue, UInt8(percent), 0, 1, 0, 0, 0])
        case .design(let index):
            guard index == nil else { throw TimeboxDisplayError.unverified("Numbered design-tab selection and its index range") }
            return Data([0x45, 5])
        case .effects(let effect):
            guard let effect else { throw TimeboxDisplayError.unverified("Bare effects selection with existing-effect preservation") }
            return Data([0x45, 3, UInt8(effect.rawValue)])
        }
    }
}
