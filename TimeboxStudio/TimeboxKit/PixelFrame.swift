import Foundation

public struct PixelFrame: Codable, Equatable, Sendable {
    public static let width = 16
    public static let height = 16

    public let width: Int
    public let height: Int
    public var pixels: [PixelRGB]

    public init(pixels: [PixelRGB], model: TimeboxModel = .evo) throws {
        width = model.width; height = model.height
        guard pixels.count == width * height else {
            throw PixelFrameError.invalidPixelCount(expected: width * height, actual: pixels.count)
        }
        self.pixels = pixels
    }

    public init(fill color: PixelRGB = PixelRGB(red: 0, green: 0, blue: 0), model: TimeboxModel = .evo) {
        width = model.width; height = model.height
        self.pixels = Array(repeating: color, count: width * height)
    }
    private enum CodingKeys: String, CodingKey { case pixels, width, height }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let width = try values.decodeIfPresent(Int.self, forKey: .width) ?? 16
        let height = try values.decodeIfPresent(Int.self, forKey: .height) ?? 16
        guard width == height, [11, 16].contains(width) else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: values, debugDescription: "Expected 11x11 Mini or 16x16 Evo pixels.")
        }
        try self.init(pixels: values.decode([PixelRGB].self, forKey: .pixels), model: width == 11 ? .mini : .evo)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(pixels, forKey: .pixels)
        // Preserve old Evo saved designs, which encoded only the pixel array.
        if width != 16 { try values.encode(width, forKey: .width); try values.encode(height, forKey: .height) }
    }
}

public enum PixelFrameError: LocalizedError, Equatable {
    case invalidPixelCount(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidPixelCount(expected, actual):
            return "Pixel frame requires \(expected) pixels, got \(actual)."
        }
    }
}
